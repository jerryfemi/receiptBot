# Official Dart image: https://hub.docker.com/_/dart
FROM dart:stable AS build

WORKDIR /app

# Resolve app dependencies.
COPY pubspec.* ./
RUN dart pub get

# Copy app source code and AOT compile it.
COPY . .
# Ensure generated code is up to date
RUN dart run build_runner build --delete-conflicting-outputs
# Create a release build.
RUN dart pub global activate dart_frog_cli
RUN dart pub global run dart_frog_cli:dart_frog build

# Build minimal serving image from AOT-compiled `/server` and required system libraries and configuration files stored in `/runtime/`
FROM dart:stable AS runtime
WORKDIR /app
COPY --from=build /app/build /app
RUN dart pub get

# Start server.
EXPOSE 8080
CMD ["dart", "bin/server.dart"]
