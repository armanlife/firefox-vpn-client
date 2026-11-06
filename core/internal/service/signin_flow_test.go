package service

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/armanlife/arman-vpn-client/core/internal/fxa"
)

// A browser sign-in is refused before anything runs when the email or the
// session token is unusable; nothing reaches the network here.
func TestStartBrowserValidation(t *testing.T) {
	r := newSignInRegistry(nil)
	valid := strings.Repeat("ab", 32)
	cases := []struct {
		name, email, token string
	}{
		{"no email", "", valid},
		{"short token", "a@b.c", "abcd"},
		{"not hex", "a@b.c", strings.Repeat("zz", 32)},
		{"empty token", "a@b.c", ""},
	}
	for _, c := range cases {
		if _, err := r.startBrowser(c.email, c.token); err == nil {
			t.Errorf("%s: startBrowser accepted bad input", c.name)
		}
	}
	if len(r.sessions) != 0 {
		t.Errorf("refused sign-ins were registered: %d", len(r.sessions))
	}
}

// The token is accepted with surrounding spaces and uppercase hex, as a
// webview bridge may deliver it.
func TestStartBrowserTokenNormalized(t *testing.T) {
	if !sessionTokenPattern.MatchString(strings.ToLower(strings.TrimSpace("  " + strings.Repeat("AB", 32) + " "))) {
		t.Error("normalized token did not match")
	}
}

func TestSignInVerificationCountsOnlyRejectedCodes(t *testing.T) {
	type reply struct {
		status     int
		body       string
		err        error
		code, text string
	}
	wrongEmail := reply{status: http.StatusBadRequest, body: `{"errno":183}`, code: signInWrongCode}
	wrongTOTP := reply{status: http.StatusOK, body: `{"success":false}`, code: signInWrongTOTP}
	network := reply{err: io.ErrUnexpectedEOF, code: signInNetwork}
	cases := []struct {
		name, method, path, step string
		replies                  []reply
		finalStep                string
	}{
		{
			name: "email code retries with the same session", method: "email-2fa",
			path: "/v1/session/verify_code", step: stepEmailCode, finalStep: stepDone,
			replies: []reply{
				wrongEmail, wrongEmail, wrongEmail, wrongEmail,
				{status: http.StatusNotAcceptable, code: signInBlocked, text: "security check blocked code verification"},
				network,
				{status: http.StatusServiceUnavailable, text: "could not verify the code right now"},
				{status: http.StatusBadRequest, body: `{"errno":107}`, text: "Enter only the digits"},
				{status: http.StatusOK, body: `{}`},
			},
		},
		{
			name: "TOTP rejection reaches the limit across a network failure", method: "totp-2fa",
			path: "/v1/session/verify/totp", step: stepTOTP, finalStep: stepFailed,
			replies: []reply{
				wrongTOTP, wrongTOTP, wrongTOTP, wrongTOTP, network,
				{status: http.StatusOK, body: `{"success":false}`, code: signInTooManyCodes},
			},
		},
		{
			name: "Mozilla throttle stops verification", method: "email-2fa",
			path: "/v1/session/verify_code", step: stepEmailCode, finalStep: stepFailed,
			replies: []reply{{status: http.StatusTooManyRequests, code: signInThrottled}},
		},
		{
			name: "invalid session stops verification", method: "email-2fa",
			path: "/v1/session/verify_code", step: stepEmailCode, finalStep: stepFailed,
			replies: []reply{{status: http.StatusUnauthorized, body: `{"errno":110,"message":"Invalid authentication token"}`, text: "Invalid authentication token"}},
		},
		{
			name: "missing TOTP result is a response error", method: "totp-2fa",
			path: "/v1/session/verify/totp", step: stepTOTP, finalStep: stepFailed,
			replies: []reply{{status: http.StatusOK, body: `{}`, text: "verification response is missing success"}},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var calls atomic.Int32
			setCoreControlPlane(t, func(r *http.Request) (*http.Response, error) {
				if r.Method == http.MethodGet && r.URL.Path == "/" {
					return coreResponse(r, http.StatusOK, "no challenge page", nil), nil
				}
				if r.Method != http.MethodPost || r.URL.Path != tc.path {
					return nil, fmt.Errorf("unexpected verification request %s %s", r.Method, r.URL.Path)
				}
				n := int(calls.Add(1))
				if n > len(tc.replies) {
					return nil, fmt.Errorf("unexpected verification attempt %d", n)
				}
				reply := tc.replies[n-1]
				if reply.err != nil {
					return nil, reply.err
				}
				return coreResponse(r, reply.status, reply.body, nil), nil
			})

			ctx, cancel := context.WithCancel(context.Background())
			s := &signIn{input: make(chan string)}
			done := make(chan struct{})
			go func() {
				defer close(done)
				resp := &fxa.LoginResponse{SessionToken: strings.Repeat("ab", 32), VerificationMethod: tc.method}
				s.finish("new@example.com", "test-account", s.verify(ctx, "new@example.com", resp))
			}()
			t.Cleanup(func() {
				cancel()
				<-done
			})

			waitStep := func(step string, want reply, n int) {
				t.Helper()
				waitForCondition(t, 2*time.Second, func() bool {
					if int(calls.Load()) != n {
						return false
					}
					view := s.snapshot()
					return view.Step == step && view.ErrorCode == want.code && strings.Contains(view.Error, want.text)
				})
			}
			waitStep(tc.step, reply{}, 0)
			for i, want := range tc.replies {
				if err := s.answer("123456"); err != nil {
					t.Fatalf("submission %d: %v", i+1, err)
				}
				step := tc.step
				if i == len(tc.replies)-1 {
					step = tc.finalStep
				}
				waitStep(step, want, i+1)
			}
		})
	}
}

// A browser sign-in waits for FxA to report its session confirmed (the
// code is entered in the page after the session was handed over), asking
// again after a failure to ask, and stops when FxA refuses the session or
// the app cancels it.
func TestBrowserSignInWaitsForConfirmation(t *testing.T) {
	previous := browserConfirmPoll
	browserConfirmPoll = time.Millisecond
	t.Cleanup(func() { browserConfirmPoll = previous })

	type reply struct {
		status int
		body   string
		err    error
	}
	unconfirmed := reply{status: http.StatusOK, body: `{"verified":false,"sessionVerified":false,"emailVerified":true}`}
	confirmed := reply{status: http.StatusOK, body: `{"verified":true,"sessionVerified":true,"emailVerified":true}`}
	cases := []struct {
		name    string
		replies []reply
		ok      bool
	}{
		{"confirmed after a code", []reply{{err: io.ErrUnexpectedEOF}, unconfirmed, unconfirmed, confirmed}, true},
		{"session ended", []reply{unconfirmed, {status: http.StatusUnauthorized, body: `{"errno":110,"message":"Invalid authentication token"}`}}, false},
		{"answer without a state", []reply{{status: http.StatusOK, body: `{}`}, confirmed}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var calls atomic.Int32
			setCoreControlPlane(t, func(r *http.Request) (*http.Response, error) {
				if r.Method != http.MethodGet || r.URL.Path != "/v1/recovery_email/status" || r.Header.Get("Authorization") == "" {
					return nil, fmt.Errorf("unexpected request %s %s", r.Method, r.URL.Path)
				}
				n := int(calls.Add(1))
				if n > len(tc.replies) {
					return nil, fmt.Errorf("unexpected status request %d", n)
				}
				reply := tc.replies[n-1]
				if reply.err != nil {
					return nil, reply.err
				}
				return coreResponse(r, reply.status, reply.body, nil), nil
			})
			s := &signIn{input: make(chan string)}
			err := s.waitSessionConfirmed(context.Background(), strings.Repeat("ab", 32))
			if (err == nil) != tc.ok {
				t.Fatalf("waitSessionConfirmed = %v, want ok=%v", err, tc.ok)
			}
			if int(calls.Load()) != len(tc.replies) {
				t.Fatalf("asked %d times, want %d", calls.Load(), len(tc.replies))
			}
		})
	}

	t.Run("cancelled by the app", func(t *testing.T) {
		setCoreControlPlane(t, func(r *http.Request) (*http.Response, error) {
			return coreResponse(r, http.StatusOK, `{"verified":false}`, nil), nil
		})
		ctx, cancel := context.WithCancel(context.Background())
		s := &signIn{input: make(chan string)}
		done := make(chan error, 1)
		go func() { done <- s.waitSessionConfirmed(ctx, strings.Repeat("ab", 32)) }()
		waitForCondition(t, 2*time.Second, func() bool {
			return strings.Contains(s.snapshot().Message, "confirmed in the browser")
		})
		cancel()
		if err := <-done; !errors.Is(err, context.Canceled) {
			t.Fatalf("waitSessionConfirmed = %v, want context.Canceled", err)
		}
	})
}
