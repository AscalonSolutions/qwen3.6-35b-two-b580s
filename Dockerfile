# Qwen3.6-35B-A3B on two Intel Arc GPUs — llama.cpp Vulkan server
#
# Build stage compiles llama.cpp at the EXACT commit this project was
# tested with (build 10069, commit 178a6c449). Do not float this pin:
# every correctness and memory claim in the README was measured on
# this commit.

FROM ubuntu:24.04 AS build

ARG LLAMACPP_COMMIT=178a6c449

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git ca-certificates cmake ninja-build g++ \
        libvulkan-dev vulkan-tools glslc glslang-tools spirv-headers pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone https://github.com/ggml-org/llama.cpp.git . \
    && git checkout ${LLAMACPP_COMMIT}

RUN cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_VULKAN=ON \
        -DLLAMA_CURL=OFF \
    && cmake --build build --target llama-server -j"$(nproc)"

# ---------------------------------------------------------------------

FROM ubuntu:24.04 AS runtime

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libvulkan1 mesa-vulkan-drivers vulkan-tools libgomp1 curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/build/bin/llama-server /usr/local/bin/llama-server
COPY --from=build /src/build/bin/*.so* /usr/local/lib/
ENV LD_LIBRARY_PATH=/usr/local/lib

# Models are mounted at /models by docker-compose; nothing is baked in.
VOLUME /models

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s \
    CMD curl -sf http://127.0.0.1:8080/health || exit 1

# Defaults match the tested configuration. CONTEXT and MODEL_FILE are
# supplied by docker-compose from the .env file.
ENTRYPOINT ["/usr/local/bin/llama-server"]
CMD ["--host", "0.0.0.0", "--port", "8080"]
