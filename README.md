# Conan Crosstoolng

Crosstool-ng setup for GCC13 on Conan


## Instructions to build

You will need Docker and Docker Compose installed. Then run:

```bash
docker compose build
```

## Instructions to use

In order to use the Docker image, you can run the following command:

```
docker run --rm -ti -v $PWD:/root/project --platform=linux/amd64 conanio/gcc13-crosstoolng:latest
```

The image contains the GCC installed under the following path: `/opt/x-tools/x86_64-linux-gnu/bin/x86_64-linux-gnu-gcc `
