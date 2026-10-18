package service

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/fxa"
	"github.com/armanlife/firefox-vpn-client/core/internal/logx"
)

const (
	// signInTimeout bounds a whole dashboard sign-in, including the time
	// the person needs to read an email or solve a CAPTCHA.
	signInTimeout = 15 * time.Minute
	// signInRetention keeps finished sign-ins visible to the dashboard.
	signInRetention = 10 * time.Minute
	// maxCodeAttempts bounds retries of a wrong verification code.
	maxCodeAttempts = 5
)

// Sign-in steps reported to the dashboard. The "need_*" steps wait for input.
const (
	stepWorking     = "working"
	stepEmailCode   = "need_email_code"
	stepTOTP        = "need_totp"
	stepUnblockCode = "need_unblock_code"
	stepCaptcha     = "need_captcha"
	stepEmailLink   = "need_email_link"
	stepDone        = "done"
	stepFailed      = "failed"
	stepCancelled   = "cancelled"
)

var errSignInCancelled = errors.New("sign-in cancelled")

// signInView is the dashboard's view of a sign-in. It never contains the
// password or any token.
type signInView struct {
	ID      string `json:"id"`
	Email   string `json:"email"`
	Step    string `json:"step"`
	Message string `json:"message"`
	// Error is what went wrong with the last answer or the sign-in, shown
	// apart from the instruction in Message.
	Error     string    `json:"error,omitempty"`
	Captcha   string    `json:"captcha,omitempty"`
	AccountID string    `json:"account_id,omitempty"`
	Updated   time.Time `json:"updated"`
}

// signIn runs one interactive Firefox Accounts sign-in in the background.
// Whenever FxA needs something from the person (a code or a CAPTCHA
// answer), it publishes a "need_*" step and waits for input.
type signIn struct {
	mu     sync.Mutex
	view   signInView
	input  chan string
	cancel context.CancelFunc
}

type signInRegistry struct {
	d        *Daemon
	mu       sync.Mutex
	sessions map[string]*signIn
}

func newSignInRegistry(d *Daemon) *signInRegistry {
	return &signInRegistry{d: d, sessions: make(map[string]*signIn)}
}

// start begins a sign-in for email and password.
func (r *signInRegistry) start(email, password string) (signInView, error) {
	email = strings.TrimSpace(email)
	if email == "" || password == "" {
		return signInView{}, errors.New("email and password are required")
	}
	var idBytes [12]byte
	if _, err := rand.Read(idBytes[:]); err != nil {
		return signInView{}, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), signInTimeout)
	s := &signIn{
		view:   signInView{ID: hex.EncodeToString(idBytes[:]), Email: email, Step: stepWorking, Message: "Signing in", Updated: time.Now()},
		input:  make(chan string),
		cancel: cancel,
	}
	r.mu.Lock()
	r.pruneLocked()
	r.sessions[s.view.ID] = s
	r.mu.Unlock()
	go s.run(ctx, r.d, email, password)
	return s.snapshot(), nil
}

func (r *signInRegistry) get(id string) (*signIn, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	s, ok := r.sessions[id]
	return s, ok
}

func (r *signInRegistry) pruneLocked() {
	for id, s := range r.sessions {
		v := s.snapshot()
		if (v.Step == stepDone || v.Step == stepFailed || v.Step == stepCancelled) && time.Since(v.Updated) > signInRetention {
			delete(r.sessions, id)
		}
	}
}

func (s *signIn) snapshot() signInView {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.view
}

func (s *signIn) set(step, message, problem, captcha string) {
	s.mu.Lock()
	s.view.Step, s.view.Message, s.view.Error, s.view.Captcha, s.view.Updated = step, message, problem, captcha, time.Now()
	s.mu.Unlock()
}

// answer delivers input for the current "need_*" step.
func (s *signIn) answer(value string) error {
	step := s.snapshot().Step
	if !strings.HasPrefix(step, "need_") {
		return errors.New("this sign-in is not waiting for input")
	}
	select {
	case s.input <- value:
		return nil
	case <-time.After(5 * time.Second):
		return errors.New("this sign-in is not waiting for input")
	}
}

// ask publishes a step that needs input and waits for it; problem says
// why the previous answer was refused, if it was.
func (s *signIn) ask(ctx context.Context, step, message, problem, captcha string) (string, error) {
	s.set(step, message, problem, captcha)
	select {
	case value := <-s.input:
		s.set(stepWorking, "Checking", "", "")
		return value, nil
	case <-ctx.Done():
		if errors.Is(ctx.Err(), context.Canceled) {
			return "", errSignInCancelled
		}
		return "", errors.New("the sign-in timed out")
	}
}

func (s *signIn) run(ctx context.Context, d *Daemon, email, password string) {
	defer s.cancel()
	accountID, err := s.signIn(ctx, d, email, password)
	switch {
	case errors.Is(err, errSignInCancelled):
		s.set(stepCancelled, "Sign-in cancelled", "", "")
	case err != nil:
		logx.Warn("dashboard sign-in failed email=%s err=%s", email, fxa.Message(err))
		s.set(stepFailed, "The account was not added.", signInFailureMessage(err), "")
	default:
		s.mu.Lock()
		s.view.AccountID = accountID
		s.mu.Unlock()
		s.set(stepDone, "Account added", "", "")
	}
}

func (s *signIn) signIn(ctx context.Context, d *Daemon, email, password string) (string, error) {
	ctx = fxa.WithCaptchaSolver(ctx, func(ctx context.Context, image string) (string, error) {
		return s.ask(ctx, stepCaptcha, "Firefox Accounts asks for a CAPTCHA. Type the characters shown.", "", image)
	})

	resp, err := fxa.Login(ctx, email, password)
	problem := ""
	for attempt := 0; fxa.Errno(err) == fxa.ErrnoRequestBlocked && attempt < maxCodeAttempts; attempt++ {
		if attempt == 0 {
			if sendErr := fxa.SendUnblockCode(ctx, email); sendErr != nil {
				return "", sendErr
			}
		} else {
			problem = "That unblock code was not accepted. Check it against the latest email from Mozilla and try again."
		}
		code, askErr := s.ask(ctx, stepUnblockCode, fmt.Sprintf("Firefox Accounts blocked this sign-in as unusual and emailed an unblock code to %s. Enter it.", email), problem, "")
		if askErr != nil {
			return "", askErr
		}
		resp, err = fxa.LoginWithUnblockCode(ctx, email, password, code)
	}
	if err != nil {
		return "", err
	}

	if !resp.Verified {
		if err := s.verify(ctx, email, resp); err != nil {
			return "", err
		}
	}

	s.set(stepWorking, "Getting the account token", "", "")
	token, err := fxa.OAuthToken(ctx, resp.SessionToken)
	if err != nil {
		return "", err
	}
	// The sign-in session is not needed once the tokens exist; left alive
	// it shows as "unknown" in the account's connected services.
	if err := fxa.DestroySession(ctx, resp.SessionToken); err != nil {
		logx.Warn("ending the sign-in session failed email=%s err=%s", email, logx.Err(err))
	}
	acc, err := d.addSignedInAccount(email, password, token)
	if err != nil {
		return "", err
	}
	return acc.ID, nil
}

// verify completes the sign-in confirmation FxA asks for.
func (s *signIn) verify(ctx context.Context, email string, resp *fxa.LoginResponse) error {
	if resp.VerificationMethod == "email" {
		if _, err := s.ask(ctx, stepEmailLink, fmt.Sprintf("Open the confirmation link sent to %s, then continue.", email), "", ""); err != nil {
			return err
		}
		return nil
	}
	step, message, verifyCode := stepEmailCode, fmt.Sprintf("Enter the verification code sent to %s.", email), fxa.VerifySession
	if resp.VerificationMethod == "totp-2fa" {
		step, message, verifyCode = stepTOTP, "Enter the code from your authenticator app.", fxa.VerifyTOTP
	}
	problem := ""
	for attempt := 0; attempt < maxCodeAttempts; attempt++ {
		code, err := s.ask(ctx, step, message, problem, "")
		if err != nil {
			return err
		}
		err = verifyCode(ctx, resp.SessionToken, strings.TrimSpace(code))
		if err == nil {
			return nil
		}
		problem = codeProblem(err, step == stepTOTP)
	}
	return errors.New("too many wrong codes; start the sign-in again")
}

// codeProblem explains a refused verification code.
func codeProblem(err error, totp bool) string {
	switch fxa.Errno(err) {
	case 105, 152, 183: // invalid verification code, invalid TOTP code, invalid or expired confirmation code
		if totp {
			return "Wrong code. Enter the code the authenticator app shows now."
		}
		return "Wrong or expired code. Use the code from the latest email from Mozilla; an older code stops working when a new one is sent."
	}
	return "The code was not accepted: " + fxa.Message(err) + "."
}

func signInFailureMessage(err error) string {
	switch fxa.Errno(err) {
	case 102:
		return "No Firefox Account exists for this email."
	case 103:
		return "Incorrect password."
	case 114:
		return "Too many attempts. Wait a while and try again."
	case 127:
		return "The unblock code was not accepted."
	}
	return fxa.Message(err)
}
