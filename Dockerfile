
# ================================
# Build Image
# ================================
FROM swift:6.0-jammy as build

WORKDIR /build

# First, resolve dependencies.
# This allows us to cache the dependency resolution step.
COPY ./Package.* ./
RUN swift package resolve

# Copy the entire project
COPY . .

# Build the application in release mode
RUN swift build -c release

# ================================
# Run Image
# ================================
FROM swift:6.0-jammy-slim

WORKDIR /app

# Copy build artifacts from the build stage
COPY --from=build /build/.build/release/App /app/App

# Copy resources (Leaf templates, etc.)
# If you have a Public folder for static files, add it here too.
COPY --from=build /build/Resources /app/Resources

# Expose the port Vapor runs on
EXPOSE 8080

# Set the entry point
ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
