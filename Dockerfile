# Official Dart image: https://hub.docker.com/_/dart
FROM dart:stable AS build

WORKDIR /app

# Resolve app dependencies.
COPY pubspec.* ./
RUN dart pub get

# Copy app source code.
COPY . .
# Ensure generated code is up to date.
RUN dart run build_runner build
# Generate the Dart Frog production server.
RUN dart pub global activate dart_frog_cli
RUN dart pub global run dart_frog_cli:dart_frog build

# Compile the server ahead of time into a single native program.
# Running `dart bin/server.dart` instead compiles everything at startup,
# which needs more than the 512 MB Render's free plan allows.
WORKDIR /app/build
RUN dart pub get
RUN dart compile exe bin/server.dart -o bin/server

# Minimal runtime image: just the compiled server, the system files Dart
# programs need (/runtime/), and the public folder (privacy page, images).
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/build/bin/server /app/bin/server
COPY --from=build /app/build/public /app/public
WORKDIR /app

# Start server. Render provides PORT; Dart Frog listens on it.
EXPOSE 8080
CMD ["/app/bin/server"]
