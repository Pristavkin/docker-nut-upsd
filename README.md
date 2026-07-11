# Network UPS Tools server

Docker image for Network UPS Tools server.

## Usage

This image provides a complete UPS monitoring service (USB driver only).

Start the container:

```console
# docker run \
	--name nut-upsd \
	--detach \
	--publish 3493:3493 \
	--device /dev/bus/usb/<bus>/<device> \
	--env SHUTDOWN_CMD="my-shutdown-command-from-container" \
	ghcr.io/pristavkin/nut-upsd:latest
```

## Starting the container automatically on USB hotplug

The UPS is connected via USB. Because USB device paths (`/dev/bus/usb/<bus>/<device>`) are assigned dynamically by the kernel, they may change after a reboot or when the device is reconnected. In addition, the UPS may not be available yet when the Docker daemon starts.

This setup uses Linux `udev` device management to automatically detect UPS connect/disconnect events. The `10-usb-ups.rules` rule triggers `docker-nut-upsd.sh`, which starts or stops the container in response to `udev` add/remove events and passes the current USB device path to Docker at runtime.

This avoids relying on a hard-coded USB device path and allows the container to start automatically whenever the UPS becomes available.

### Setup

1. Clone this repository to `/srv/nut-upsd` on the host:

   ```console
   # git clone https://github.com/pristavkin/docker-nut-upsd.git /srv/nut-upsd
   ```

2. Find your UPS vendor and product IDs using `lsusb`, then update them in both `10-usb-ups.rules` (`idVendor`/`idProduct`) and your environment file (`VENDOR_ID`/`DEVICE_ID`):

   ```console
   # cp /srv/nut-upsd/.env.example /srv/nut-upsd/.env
   # chmod 600 /srv/nut-upsd/.env
   # $EDITOR /srv/nut-upsd/.env              # VENDOR_ID, DEVICE_ID, ADMIN_PASSWORD, API_PASSWORD, ...
   # $EDITOR /srv/nut-upsd/10-usb-ups.rules # idVendor, idProduct
   ```

3. Copy the `udev` rules file into place and reload `udev`:

   ```console
   # cp /srv/nut-upsd/10-usb-ups.rules /etc/udev/rules.d/
   # udevadm control --reload-rules
   ```

4. Reconnect the UPS, or reboot the host with the UPS already connected. `udev` will generate add events for existing devices during boot.

Connecting the UPS runs:

```console
docker-nut-upsd.sh start
```

The script resolves the current `/dev/bus/usb/...` path and starts the container with the correct device mounted.

Disconnecting the UPS runs:

```console
docker-nut-upsd.sh stop
```

The `docker-nut-upsd.sh` logs its actions through the system logger using the `docker-nut-upsd` identifier. When started by `udev`, the script does not write output to the terminal; all messages are available through the systemd journal.

View the logs with:

```console
# journalctl -t docker-nut-upsd -f
```

`docker-nut-upsd.sh` reads all configuration from an environment file (`.env` next to the script by default, or `$ENV_FILE`) instead of values hard-coded in the script. This keeps credentials out of version control.

## Additional considerations

- **Host/VM shutdown orchestration**: if the host or its VMs should also be shut down (not just this container), point `SHUTDOWN_CMD` at a real command in the env file; the image ships `govc` and `bash` for that.
- **Running the script manually**: The script logs through `logger` instead of stdout. Running `docker-nut-upsd.sh start` or `docker-nut-upsd.sh stop` interactively will not print output to the terminal. Check the journal instead:

  ```console
  # journalctl -t docker-nut-upsd
  ```

## Configuration environment variables

This image supports customization via environment variables.

### UPS_NAME

*Default value*: `ups`

The name of the UPS.

### UPS_DESC

*Default value*: `Eaton 5SC`

This allows you to set a brief description that upsd will provide to clients that ask for a list of connected equipment.

### UPS_DRIVER

*Default value*: `usbhid-ups`

This specifies which program will be monitoring this UPS.

### UPS_PORT

*Default value*: `auto`

This is the serial port where the UPS is connected.

### API_USER

*Default value*: `upsmon`

This is the username used for communication between upsmon and upsd processes.

### API_PASSWORD

*Default value*: `secret`

This is the password for the upsmon user.

### SHUTDOWN_CMD

*Default value*: `echo 'System shutdown not configured!'`

This is the command upsmon will run when the system needs to be brought down. The command will be run from inside the container.

