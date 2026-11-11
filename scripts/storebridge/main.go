package main

import (
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"syscall"

	cookiejar "github.com/juju/persistent-cookiejar"
	"github.com/majd/ipatool/v2/pkg/appstore"
	"github.com/majd/ipatool/v2/pkg/util/machine"
	"github.com/majd/ipatool/v2/pkg/util/operatingsystem"
)

type request struct {
	Operation string
	Directory string
	Email     string
	Password  string
	Code      string
	AppID     int64
	VersionID string
}
type response struct {
	Account *appstore.Account `json:"account,omitempty"`
	Plist   []byte            `json:"plist,omitempty"`
	Error   string            `json:"error,omitempty"`
	Code    string            `json:"code,omitempty"`
}
type fileStore struct {
	path    string
	entries map[string][]byte
}

func (s *fileStore) Get(key string) ([]byte, error) {
	data, ok := s.entries[key]
	if !ok {
		return nil, os.ErrNotExist
	}
	return data, nil
}
func (s *fileStore) Set(key string, data []byte) error {
	s.entries[key] = data
	return s.save()
}
func (s *fileStore) Remove(key string) error {
	delete(s.entries, key)
	return s.save()
}
func (s *fileStore) save() error {
	data, err := json.Marshal(s.entries)
	if err != nil {
		return err
	}
	temp, err := os.CreateTemp(filepath.Dir(s.path), ".session-")
	if err != nil {
		return err
	}
	defer os.Remove(temp.Name())
	if _, err = temp.Write(data); err != nil {
		temp.Close()
		return err
	}
	if err = temp.Close(); err != nil {
		return err
	}
	return os.Rename(temp.Name(), s.path)
}
func execute(req request) (response, error) {
	if req.Email == "" || !filepath.IsAbs(req.Directory) {
		return response{}, errors.New("invalid session directory or account")
	}
	if err := os.MkdirAll(req.Directory, 0700); err != nil {
		return response{}, err
	}
	lock, err := os.OpenFile(filepath.Join(req.Directory, "session.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return response{}, err
	}
	defer lock.Close()
	// Different Swift tasks may address the same session. Process termination releases this lock.
	if err = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		return response{}, err
	}
	defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
	state := &fileStore{path: filepath.Join(req.Directory, "session.json"), entries: map[string][]byte{}}
	data, err := os.ReadFile(state.path)
	if err == nil {
		if err = json.Unmarshal(data, &state.entries); err != nil {
			return response{}, err
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return response{}, err
	}
	if state.entries == nil {
		return response{}, errors.New("invalid session state")
	}
	jar, err := cookiejar.New(&cookiejar.Options{Filename: filepath.Join(req.Directory, "cookies.json")})
	if err != nil {
		return response{}, err
	}
	system := operatingsystem.New()
	client := appstore.NewAppStore(appstore.Args{Keychain: state, CookieJar: jar, OperatingSystem: system, Machine: machine.New(machine.Args{OS: system})})
	var result response
	switch req.Operation {
	case "login":
		output, loginErr := client.Login(appstore.LoginInput{Email: req.Email, Password: req.Password, AuthCode: req.Code})
		err = loginErr
		if err == nil {
			output.Account.Password = ""
			result.Account = &output.Account
		}
	case "downloadInfo", "purchase":
		info, infoErr := client.AccountInfo()
		if infoErr != nil || info.Account.Email != req.Email {
			return response{Code: "tokenExpired"}, nil
		}
		if req.Operation == "downloadInfo" {
			result.Plist, err = appstore.IPADownDownloadInfo(client, info.Account, req.AppID, req.VersionID)
		} else {
			err = client.Purchase(appstore.PurchaseInput{Account: info.Account, App: appstore.App{ID: req.AppID}, Platform: appstore.PlatformIPhone})
			if errors.Is(err, appstore.ErrLicenseAlreadyExists) {
				err = nil
			}
		}
	default:
		return response{}, errors.New("unsupported operation")
	}
	// Preserve the 2FA challenge cookies too.
	saveErr := jar.Save()
	if err == nil {
		err = saveErr
	}
	return result, err
}
func main() {
	syscall.Umask(0077)
	var req request
	result := response{}
	err := json.NewDecoder(io.LimitReader(os.Stdin, 1024*1024)).Decode(&req)
	if err == nil {
		result, err = execute(req)
	}
	if err != nil {
		switch {
		case errors.Is(err, appstore.ErrAuthCodeRequired):
			result.Code = "codeRequired"
		case errors.Is(err, appstore.ErrPasswordTokenExpired):
			result.Code = "tokenExpired"
		case errors.Is(err, appstore.ErrLicenseRequired):
			result.Code = "licenseRequired"
		default:
			result.Error = err.Error()
		}
	}
	json.NewEncoder(os.Stdout).Encode(result)
}
