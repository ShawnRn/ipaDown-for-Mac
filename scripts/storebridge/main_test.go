package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestPrivateSessionRoundTrip(t *testing.T) {
	directory := t.TempDir()
	store := &fileStore{path: filepath.Join(directory, "session.json"), entries: map[string][]byte{}}
	secret := []byte{0, 1, 2, 255, 10}
	if err := store.Set("anisette-v4", secret); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	entries := map[string][]byte{}
	if err = json.Unmarshal(data, &entries); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(entries["anisette-v4"], secret) {
		t.Fatal("binary authentication state changed")
	}
	info, err := os.Stat(store.path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatalf("session permissions %o", info.Mode().Perm())
	}
	if err = store.Remove("anisette-v4"); err != nil {
		t.Fatal(err)
	}
	if _, err = store.Get("anisette-v4"); !os.IsNotExist(err) {
		t.Fatal("deleted state survived")
	}
}

func TestMissingOrDifferentAccountRequiresRefresh(t *testing.T) {
	for _, email := range []string{"", "another@example.invalid"} {
		directory := t.TempDir()
		if email != "" {
			store := &fileStore{path: filepath.Join(directory, "session.json"), entries: map[string][]byte{}}
			if err := store.Set("account", []byte(`{"email":"another@example.invalid"}`)); err != nil {
				t.Fatal(err)
			}
		}
		result, err := execute(request{Operation: "downloadInfo", Directory: directory, Email: "requested@example.invalid", AppID: 590338362})
		if err != nil {
			t.Fatal(err)
		}
		if result.Code != "tokenExpired" {
			t.Fatal("must not use another account's session")
		}
	}
}

func TestInvalidDirectoryIsRejected(t *testing.T) {
	if _, err := execute(request{Operation: "login", Directory: "relative", Email: "test@example.invalid"}); err == nil {
		t.Fatal("relative session directory accepted")
	}
}
