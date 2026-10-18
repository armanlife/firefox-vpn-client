package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"text/tabwriter"
	"time"

	"golang.org/x/term"

	"github.com/armanlife/firefox-vpn-client/core/internal/accounts"
	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/fxa"
	"github.com/armanlife/firefox-vpn-client/core/internal/guardian"
	"github.com/armanlife/firefox-vpn-client/core/internal/logx"
	"github.com/armanlife/firefox-vpn-client/core/internal/proxy"
	"github.com/armanlife/firefox-vpn-client/core/internal/service"
)

// runAddAccount signs in interactively and stores the account at the end
// of the priority order.
func runAddAccount(paths service.DataPaths) error {
	cfg, err := service.LoadConfig(paths, false)
	if err != nil {
		return err
	}
	store, _, err := service.OpenAccounts(paths, &cfg)
	if err != nil {
		return err
	}

	token, email, password := interactiveSignIn()
	now := time.Now()
	acc, created, err := store.Add(email, &fxa.SavedTokens{
		AccessToken:  token.AccessToken,
		RefreshToken: token.RefreshToken,
		Scope:        token.Scope,
		ObtainedAt:   now,
		ExpiresIn:    token.ExpiresIn,
	}, now)
	if err != nil {
		return err
	}
	if err := store.SetPassword(acc.ID, password); err != nil {
		fmt.Println("Saving the password failed:", err)
	}
	list, err := store.List()
	if err != nil {
		return err
	}
	if _, changed := service.ReconcileAccountOrder(&cfg, list); changed {
		if err := config.Save(paths.Config, cfg); err != nil {
			return err
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), proxy.APIRequestTimeout)
	usage, usageErr := guardian.FetchProxyUsage(ctx, cfg.Network.GuardianEndpoint, token.AccessToken)
	cancel()
	if usageErr == nil && usage != nil {
		u := proxy.AccountUsage(usage)
		acc.Usage = &u
		if err := store.Save(acc); err != nil {
			logx.Warn("saving account usage failed: %s", logx.Err(err))
		}
	}

	if created {
		fmt.Printf("Account added: %s (id %s)\n", acc.Name(), acc.ID)
	} else {
		fmt.Printf("Account updated with new credentials: %s (id %s)\n", acc.Name(), acc.ID)
	}
	if acc.Usage != nil {
		fmt.Printf("Quota: %s\n", accounts.FormatUsage(acc.Usage))
	} else {
		fmt.Println("Quota: unknown until the account is first used")
	}
	return nil
}

// runListAccounts prints the stored accounts in priority order.
func runListAccounts(paths service.DataPaths) error {
	cfg, err := service.LoadConfig(paths, false)
	if err != nil {
		return err
	}
	store, _, err := service.OpenAccounts(paths, &cfg)
	if err != nil {
		return err
	}
	var all []string
	enabled := make(map[string]bool)
	for _, ref := range cfg.Accounts.Order {
		all = append(all, ref.ID)
		enabled[ref.ID] = ref.Enabled
	}
	mgr, err := accounts.NewManager(store, all, accounts.Policy{ThresholdPercent: cfg.Accounts.SwitchThresholdPercent}, paths.State)
	if err != nil {
		return err
	}
	active, _ := mgr.Active()

	fmt.Printf("Data folder: %s\nSwitch threshold: %g%% of each account's quota\n\n", paths.Dir, cfg.Accounts.SwitchThresholdPercent)
	if len(all) == 0 {
		fmt.Println("No accounts. Add one with -add-account.")
		return nil
	}
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "#\tACTIVE\tACCOUNT\tID\tSTATUS\tUSAGE\tNOTE")
	for i, acc := range mgr.Accounts() {
		marker := ""
		if acc.ID == active.ID {
			marker = "*"
		}
		status := string(acc.Status)
		if !enabled[acc.ID] {
			status = "disabled"
		}
		note := acc.Reason
		if !acc.RetryAt.IsZero() {
			note = strings.TrimSpace(note + " until " + acc.RetryAt.Local().Format("2006-01-02 15:04"))
		}
		fmt.Fprintf(w, "%d\t%s\t%s\t%s\t%s\t%s\t%s\n", i+1, marker, acc.Name(), acc.ID, status, accounts.FormatUsage(acc.Usage), note)
	}
	return w.Flush()
}

// runSetDashboardLogin sets or clears the dashboard credentials on the
// terminal, for headless servers whose dashboard is not reachable yet.
func runSetDashboardLogin(paths service.DataPaths) error {
	cfg, _, err := config.Load(paths.Config)
	if err != nil {
		return err
	}
	reader := bufio.NewReader(os.Stdin)
	fmt.Print("Dashboard username (empty disables the login): ")
	username, _ := reader.ReadString('\n')
	username = strings.TrimSpace(username)
	if username == "" {
		cfg.Dashboard.Username, cfg.Dashboard.PasswordHash = "", ""
		if err := config.Save(paths.Config, cfg); err != nil {
			return err
		}
		fmt.Println("Dashboard login disabled. Restart the service to apply.")
		return nil
	}
	password, err := readPassword("Dashboard password: ")
	if err != nil {
		return err
	}
	confirm, err := readPassword("Repeat the password: ")
	if err != nil {
		return err
	}
	if password != confirm {
		return errors.New("the passwords do not match")
	}
	hash, err := service.HashDashboardPassword(password)
	if err != nil {
		return err
	}
	cfg.Dashboard.Username, cfg.Dashboard.PasswordHash = username, hash
	if err := config.Save(paths.Config, cfg); err != nil {
		return err
	}
	fmt.Println("Dashboard login saved. Restart the service to apply.")
	return nil
}

func readPassword(prompt string) (string, error) {
	fmt.Print(prompt)
	data, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Println()
	if err != nil {
		return "", fmt.Errorf("reading password: %w", err)
	}
	return string(data), nil
}

// interactiveSignIn prompts for the account email and password on the
// terminal, completes any sign-in verification, and returns the issued
// OAuth credentials with the email. It exits the process on failure.
func interactiveSignIn() (*fxa.TokenResponse, string, string) {
	email, password := promptCredentials()

	fmt.Print("Logging in... ")
	loginCtx, loginCancel := context.WithTimeout(context.Background(), proxy.APIRequestTimeout)
	loginResp, err := fxa.Login(loginCtx, email, password)
	loginCancel()
	if err != nil {
		fmt.Printf("failed: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("OK")

	if !loginResp.Verified {
		verifySessionInteractively(email, loginResp.SessionToken, loginResp.VerificationMethod)
	}

	fmt.Print("Getting OAuth token... ")
	tokenCtx, tokenCancel := context.WithTimeout(context.Background(), proxy.APIRequestTimeout)
	token, err := fxa.OAuthToken(tokenCtx, loginResp.SessionToken)
	if err == nil {
		// Not needed once the tokens exist; left alive it shows as
		// "unknown" in the account's connected services.
		if destroyErr := fxa.DestroySession(tokenCtx, loginResp.SessionToken); destroyErr != nil {
			logx.Warn("ending the sign-in session failed err=%s", logx.Err(destroyErr))
		}
	}
	tokenCancel()
	if err != nil {
		fmt.Printf("failed: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("OK")
	return token, email, password
}

// verifySessionInteractively prompts for the confirmation code FxA sent to
// the account email at login time and retries until the session is verified.
func verifySessionInteractively(email, sessionToken, verificationMethod string) {
	reader := bufio.NewReader(os.Stdin)

	if verificationMethod == "email" {
		// Server fell back to the confirmation-link flow; there is no
		// code to enter.
		fmt.Printf("This sign-in must be confirmed: a confirmation link was sent to %s.\n", email)
		fmt.Print("Open the link from the email, then press Enter here to continue: ")
		if _, err := reader.ReadString('\n'); err != nil {
			logx.Error("reading confirmation input failed: %v", err)
			os.Exit(1)
		}
		return
	}

	fmt.Printf("This sign-in must be confirmed: a verification code was sent to %s.\n", email)
	for {
		fmt.Print("Enter the verification code from the email: ")
		line, err := reader.ReadString('\n')
		if err != nil {
			logx.Error("reading verification code failed: %v", err)
			os.Exit(1)
		}
		code := strings.TrimSpace(line)
		if code == "" {
			continue
		}

		ctx, cancel := context.WithTimeout(context.Background(), proxy.APIRequestTimeout)
		err = fxa.VerifySession(ctx, sessionToken, code)
		cancel()
		if err == nil {
			fmt.Println("Session verified.")
			return
		}
		fmt.Printf("Verification failed: %v\n", err)
	}
}

func promptCredentials() (string, string) {
	reader := bufio.NewReader(os.Stdin)
	fmt.Println("=== Firefox VPN Proxy ===")
	fmt.Println()
	fmt.Print("Firefox Account email: ")
	email, _ := reader.ReadString('\n')

	fmt.Print("Password: ")
	passwordBytes, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Println()
	if err != nil {
		logx.Error("reading password failed: %v", err)
		os.Exit(1)
	}
	return strings.TrimSpace(email), string(passwordBytes)
}
