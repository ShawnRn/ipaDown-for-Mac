package appstore

import (
	"context"
	"errors"
	"howett.net/plist"
	"strings"
)

// IPADownDownloadInfo retains the download manager's existing transfer and sinf pipeline.
func IPADownDownloadInfo(client AppStore, account Account, appID int64, versionID string) ([]byte, error) {
	store, ok := client.(*appstore)
	if !ok {
		return nil, errors.New("unsupported Store client")
	}
	mac, err := store.machine.MacAddress()
	if err != nil {
		return nil, err
	}
	guid := strings.ReplaceAll(strings.ToUpper(mac), ":", "")
	result, _, err := store.sendDownloadProduct(context.Background(), account, App{ID: appID}, guid, versionID, PlatformIPhone)
	if err != nil {
		return nil, err
	}
	return plist.Marshal(result.Data, plist.XMLFormat)
}
