# mcpe-docker Dockerfile

[Docker](http://docker.com) container to build [Minecraft on Linux](https://mcpelauncher.readthedocs.io/en/latest/getting_started.html).


## Usage

### Install

Or build `mcpe-docker` from source:
```
docker build -t mcpe-docker . | tee build.log
```

### Run

This image is designed to build MCPE Launcher.

```
docker run -it --rm -v $(pwd):/workdir -w="/workdir" mcpe-docker bash
```

To copy the output files from the fully built container:
```
docker create -it --name copy mcpe-docker bash
docker cp copy:/opt/output/ .
docker rm -f copy
```
