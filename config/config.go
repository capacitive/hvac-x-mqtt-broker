package config

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v2"

)

type Config struct {
	Server struct {
		Host         string `yaml:"host"`
		Port         string `yaml:"port"`
		SendCommands bool   `yaml:"sendcommands"`
	} `yaml:"server"`
	Devices struct {
		Plugs struct {
			IDList  []string `yaml:"idlist,flow"`
			Command string   `yaml:"command"`
		} `yaml:"plugs"`
		Switches struct {
			IDList  []string `yaml:"idlist,flow"`
			Command string   `yaml:"command"`
		} `yaml:"switches"`
	} `yaml:"devices"`
	CloudApi struct {
		BaseUrl      string `yaml:"baseurl"`
		Telemetry    string `yaml:"telemetry"`
		Device       string `yaml:"device"`
		Cron         string `yaml:"cron"`
		CallsEnabled bool   `yaml:"callsenabled"`
	} `yaml:"cloudapi"`
}

func LoadConfig() (cfg Config, err error) {
	

	exe, err := os.Executable()
	exePath := filepath.Dir(exe)
	fmt.Println("config file loaded from path:", exePath)

	file, err := os.Open(exePath + "/broker-config.yml")
	if err != nil {
		return Config{}, err
	}
	defer file.Close()

	decoder := yaml.NewDecoder(file)
	err = decoder.Decode(&cfg)
	if err != nil {
		return Config{}, err
	}

	return cfg, nil
}
