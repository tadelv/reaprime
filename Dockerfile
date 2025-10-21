FROM ubuntu:22.04

# Install dependencies for Flutter Linux builds
RUN apt-get update && apt-get install -y \
    curl git unzip xz-utils zip \
    libglu1-mesa clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Install Flutter SDK
RUN git clone https://github.com/flutter/flutter.git -b stable /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"

# Pre-cache Flutter and enable Linux desktop
RUN flutter config --enable-linux-desktop && \
    flutter precache --linux

WORKDIR /app
CMD ["bash"]
