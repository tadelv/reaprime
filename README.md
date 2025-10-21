# Reasonable Espresso App - 1 

> ReaPrime (R1) is a gateway app to the next generation of interfaces for the DE1. An API first approach makes it help you
> focus on developing modern and sleek UIs, that are easy on the eyes as well as a delight to use. 


## API
read more about the api in [v1 api doc](./api_v1.md) or use the [OpenApi yaml](./api_v1.yaml).

## Supported platforms
The primary platform for ReaPrime is Android, as it runs on the tablet the DE1 ships with.
Of course, R1 can run as a service in the background, neatly tucked out of the way, but still keeping a stable
connection between your app and the DE1.

### What does it support?
Currently, R1 supports the most basic of features, but enough to support the main workflows

#### DE1 supported operations
- Query and set machine state (turn off/on, start espresso on machines without GHC, stop the shot)
- Set machine settings such as hot water temperature, steam temperature etc.
- Upload v2 json profiles to the machine (the ones de1app stores in `profiles_v2`)

- Exposed websockets for realtime shot updates and other values that might change frequently

#### Scale supported operations
- Tare the scale
- Exposed websocket for weight snapshots

##### Currently supported scales:
- Felicita Arc
- Decent Scale
- Bookoo


### Build for Linux arm64 in container:

`docker compose run --rm flutter-build flutter build linux --release`
