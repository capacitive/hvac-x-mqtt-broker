module mqtt-broker

go 1.21.3

require (
	github.com/antchfx/jsonquery v1.3.3
	github.com/mochi-mqtt/server/v2 v2.4.1
	mqtt-broker/config v1.0.0
)

require (
	github.com/antchfx/xpath v1.2.3 // indirect
	github.com/golang/groupcache v0.0.0-20210331224755-41bb18bfe9da // indirect
	github.com/gorilla/websocket v1.5.0 // indirect
	github.com/niemeyer/pretty v0.0.0-20200227124842-a10e7caefd8e // indirect
	github.com/rs/xid v1.4.0 // indirect
	gopkg.in/check.v1 v1.0.0-20200227125254-8fa46927fb4f // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)

replace mqtt-broker/config v1.0.0 => ./config
