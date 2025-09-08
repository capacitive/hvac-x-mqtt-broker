module mqtt-broker

go 1.21.3

require (
	github.com/antchfx/jsonquery v1.3.3
	github.com/gorilla/websocket v1.5.0
	github.com/mochi-mqtt/server/v2 v2.4.1
	mqtt-broker/config v1.0.0
	mqtt-broker/logger v1.0.0
	mqtt-broker/updater v1.0.0
	google.golang.org/grpc v1.58.3
)

require (
	github.com/antchfx/xpath v1.2.3 // indirect
	github.com/golang/groupcache v0.0.0-20210331224755-41bb18bfe9da // indirect
	github.com/gorilla/websocket v1.5.0 // indirect
	github.com/rs/xid v1.4.0 // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)

replace (
	mqtt-broker/config v1.0.0 => ./config
	mqtt-broker/logger v1.0.0 => ./logger
	mqtt-broker/updater v1.0.0 => ./updater
)
