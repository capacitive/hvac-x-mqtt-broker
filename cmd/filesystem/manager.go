package cmd

import (
	"os"

	"github.com/mcuadros/go-defaults"
)

func NewOutTreeFS() *OutTreeDir {
	filesys := new(OutTreeDir)
	defaults.SetDefaults(filesys)
	return filesys
}

func CreateOutTreeDir(dirname string) (string, error) {
	err := os.Mkdir(dirname, 0755)
	if err != nil {
		return "", err
	}

	//STOP making dumb mistakes like this!
	// dir, _ := os.DirFS(dirname).Open(dirname)
	// fileinfo, _ := dir.Stat()

	fileinfo, err := os.Stat(dirname)
	if err != nil {
		return "", err
	}
	return fileinfo.Name(), nil
}

func DeleteOutTreeDir(dirname string) error {
	err := os.Remove(dirname)
	if err != nil {
		return err
	}
	return nil
}
