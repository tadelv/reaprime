# Reasonable Espresso App - 1 

> ReaPrime (R1) is a gateway app to the next generation of interfaces for the DE1. An API first approach makes it help you
> focus on developing modern and sleek UIs, that are easy on the eyes as well as a delight to use. 


## API
To browse the REA API, start REA and then point your browser to [localhost:4001](http://localhost:4001).

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

### Plugins

REA features a plugin system, for dynamic expansion of the user experience.

[Read here](/Plugins.md) for more information.

## Building

I'll skip through Flutter SDK install for now, google has all the answers.  

### Build on your machine

For versioning purposes, a build script is included, that injects certain environment vars into the build process.  
If you want to take advantage of that, make sure you run:
`./flutter_with_commit.sh run`

### Build for Linux arm64 in container:

Have Colima installed. Then `make build-arm`


## Reasons and credits:

REA stands for "Reasonable Espresso App". Provided you use it with a Decent Espresso machine, it might help you brew a reasonably decent espresso.  

Credit for the name and thanks for all the support, goes to [@randomcoffeesnob](https://github.com/randomcoffeesnob).  
Also thanks to [@mimoja](https://github.com/mimoja) for the first Flutter app version.
