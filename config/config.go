package config

import (
	"os"

	"gopkg.in/yaml.v2"
)

type Config struct {
	Server struct {
		Host           string `yaml:"host"`
		Port           string `yaml:"port"`
		ControlDevices bool   `yaml:"controldevices"`
	} `yaml:"server"`
	CloudApi struct {
		BaseUrl      string `yaml:"baseurl"`
		Telemetry    string `yaml:"telemetry"`
		Device       string `yaml:"device"`
		Cron         string `yaml:"cron"`
		CallsEnabled bool   `yaml:"callsenabled"`
	} `yaml:"cloudapi"`
}

func LoadConfig() (cfg Config, err error) {
	file, err := os.Open("./broker-config.yml")
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
