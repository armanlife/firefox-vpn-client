package fxa

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/controlplane"
)

func TestSolvePowFindsSuffix(t *testing.T) {
	t.Parallel()

	base := "challenge-base-string"
	target := sha256.Sum256([]byte(base + "Xk"))

	answer, ok := solvePow(base, hex.EncodeToString(target[:]))
	if !ok {
		t.Fatal("solvePow did not find a solution")
	}
	if answer != "Xk" {
		t.Fatalf("expected answer Xk, got %q", answer)
	}
}

func TestSolvePowRejectsInvalidTarget(t *testing.T) {
	t.Parallel()

	if _, ok := solvePow("base", "not-hex"); ok {
		t.Fatal("expected failure for non-hex target")
	}
	// A hash that does not end on any two-character alphanumeric suffix.
	missing := make([]byte, sha256.Size)
	if _, ok := solvePow("base-that-does-not-match", hex.EncodeToString(missing)); ok {
		t.Fatal("expected no solution for zero hash")
	}
}

func TestParseChallengeInitExtractsToken(t *testing.T) {
	t.Parallel()

	script := `var noise = {init:function(){}};something.init([1,2]);` +
		`;init([{"ty":"pat","data":{}}], "token-abc", "/_fs-ch-1T1wmsGaOgGaSxcX", true);`

	challenges, token, err := parseChallengeInit(script)
	if err != nil {
		t.Fatalf("parseChallengeInit returned error: %v", err)
	}
	if token != "token-abc" {
		t.Fatalf("expected token-abc, got %q", token)
	}
	if len(challenges) != 1 || challenges[0].Ty != "pat" {
		t.Fatalf("unexpected challenges: %+v", challenges)
	}
}

func TestParseChallengeInitPowData(t *testing.T) {
	t.Parallel()

	script := `;init([{"ty":"pow","data":{"base":"b","expires":"123","hmac":"h","hash":"00"}}], "tok", "/_fs-ch-x", true);`
	challenges, _, err := parseChallengeInit(script)
	if err != nil {
		t.Fatalf("parseChallengeInit returned error: %v", err)
	}
	if len(challenges) != 1 || challenges[0].Ty != "pow" {
		t.Fatalf("unexpected challenges: %+v", challenges)
	}

	var d fastlyPowData
	if err := json.Unmarshal(challenges[0].Data, &d); err != nil {
		t.Fatalf("unmarshalling pow data: %v", err)
	}
	if d.Base != "b" || d.HMAC != "h" || d.Expires != "123" {
		t.Fatalf("unexpected pow data: %+v", d)
	}
}

// A caller waiting for another solve gives up when its context ends, and
// leaves the slot to its holder.
func TestChallengeSlotWaiterGivesUp(t *testing.T) {
	challengeSolveSlot <- struct{}{} // another solve holds the slot
	defer func() { <-challengeSolveSlot }()
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	start := time.Now()
	if err := solveFastlyChallenge(ctx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("want DeadlineExceeded, got %v", err)
	}
	if waited := time.Since(start); waited > 2*time.Second {
		t.Fatalf("the waiter did not give up in time: %s", waited)
	}
	if len(challengeSolveSlot) != 1 {
		t.Fatal("the waiter must not take or release the holder's slot")
	}
}

// The solver's requests carry the User-Agent the API calls do.
func TestChallengeRequestsCarryFirefoxUserAgent(t *testing.T) {
	var got []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = append(got, r.Header.Get("User-Agent"))
		_, _ = w.Write([]byte(`{"auth":"a"}`))
	}))
	defer server.Close()
	ctx := context.Background()
	if _, err := fetchText(ctx, server.Client(), server.URL+"/"); err != nil {
		t.Fatal(err)
	}
	if _, err := fetchPAT(ctx, server.Client(), server.URL, "token"); err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("requests seen: %d", len(got))
	}
	for _, ua := range got {
		if ua != controlplane.FirefoxUserAgent() {
			t.Fatalf("User-Agent %q, want %q", ua, controlplane.FirefoxUserAgent())
		}
	}
}
