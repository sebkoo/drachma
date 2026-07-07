# Containerize drachma-server for automated deployment. Multi-stage: build with
# the full Swift toolchain, ship a slim runtime image.
FROM swift:6.1-jammy AS build
WORKDIR /app
COPY Package.swift Package.resolved ./
RUN swift package resolve
# Copy the whole package: SPM validates every target's path at manifest load,
# so all target directories must be present even to build one product.
# (.dockerignore keeps .build/.git/docs/xcodeproj out of the context.)
COPY . .
RUN swift build -c release --product drachma-server

FROM swift:6.1-jammy-slim
WORKDIR /app
COPY --from=build /app/.build/release/drachma-server /app/drachma-server
EXPOSE 8080
ENV PORT=8080
# A non-root user, because this is a network service.
RUN useradd --create-home drachma
USER drachma
ENTRYPOINT ["/app/drachma-server"]
