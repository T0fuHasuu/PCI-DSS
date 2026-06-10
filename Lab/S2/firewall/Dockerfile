FROM alpine:3.23

# Install iptables for packet filtering
RUN apk add --no-cache iptables

# Set working directory
WORKDIR /fw

# Copy all script files into the container
COPY entrypoint.sh internal-rules.sh perimeter-rules.sh ./

# Make all shell scripts executable
RUN chmod +x *.sh

# Run the entrypoint script
ENTRYPOINT ["./entrypoint.sh"]