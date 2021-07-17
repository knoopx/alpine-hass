#!/bin/sh

set -xe

TARGET_HOSTNAME="homeassistant"
TARGET_USER_NAME="pi"

apk del wpa_supplicant wireless-tools wireless-regdb iw
rm /boot/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf

setup-hostname $TARGET_HOSTNAME
echo "127.0.0.1    $TARGET_HOSTNAME $TARGET_HOSTNAME.localdomain" > /etc/hosts

cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

hostname $TARGET_HOSTNAME
EOF

# home assistant
apk add autoconf gcc jpeg-dev libffi-dev make musl-dev openjpeg openssl-dev py3-pip python3 python3-dev tiff tzdata zlib-dev
apk add py3-cffi py3-cryptography py3-defusedxml py3-numpy py3-pandas py3-pillow py3-sqlalchemy py3-yaml py3-yarl py3-multidict # prevent pip from compling these packages

pip install homeassistant

cat <<EOF > /etc/init.d/hass
#!/sbin/openrc-run
command="hass"
command_background=true
command_user="pi"
pidfile="/run/hass.pid"
EOF
chmod +x /etc/init.d/hass
rc-update add hass default

# hacs
apk add wget bash
wget -q -O - https://install.hacs.xyz | bash -

# mqtt
apk add mosquitto
cat <<EOF > /etc/mosquitto/mosquitto.conf
allow_anonymous true
EOF
rc-update add mosquitto default

# zigbee2mqtt

apk add nodejs npm python3 linux-headers
npm install -g --no-update-notifier --no-audit --no-fund zigbee2mqtt

cat <<EOF > /etc/init.d/zigbee2mqtt
#!/sbin/openrc-run
command="/usr/local/bin/zigbee2mqtt"
command_background=true
command_user="$TARGET_USER_NAME"
pidfile="/run/zigbee2mqtt.pid"
EOF
chmod +x /etc/init.d/zigbee2mqtt
rc-update add zigbee2mqtt default

# node-red

apk add nodejs npm
npm install -g --no-update-notifier --no-audit --no-fund node-red

cat <<RUN | su - $TARGET_USER_NAME
mkdir -p ~/.node-red
cat <<EOF > ~/.node-red/package.json
{
  "name": "node-red-project",
  "description": "node-red user packages",
  "version": "0.0.1",
  "private": true,
  "dependencies": {}
}
EOF
cd ~/.node-red && npm install --no-update-notifier --no-audit --no-fund @node-red-contrib-themes/midnight-red node-red-contrib-finite-statemachine node-red-contrib-home-assistant-websocket node-red-contrib-persistent-fsm
RUN

cat <<EOF > /etc/init.d/node-red
#!/sbin/openrc-run
command="/usr/local/bin/node-red-pi"
command_args="--max-old-space-size=256"
command_background=true
command_user="$TARGET_USER_NAME"
pidfile="/run/node-red.pid"
EOF
chmod +x /etc/init.d/node-red
rc-update add node-red default

# web server
apk add caddy

cat <<EOF > /etc/caddy/Caddyfile
localhost

encode gzip

handle /node-red* {
  uri strip_prefix node-red
  reverse_proxy 127.0.0.1:1880
}

handle /zigbee2mqtt* {
  uri strip_prefix zigbee2mqtt
  reverse_proxy 127.0.0.1:8099
}

handle {
  reverse_proxy 127.0.0.1:8123
}
EOF
rc-update add caddy default

# logrotate
apk add logrotate
mv /etc/periodic/daily/logrotate /etc/periodic/15min/

cat <<EOF > /etc/logrotate.d/homeassistant
hourly

rotate 0
nocreate
notifempty
missingok

/home/$TARGET_USER_NAME/.homeassistant/home-assistant.log {}
/home/$TARGET_USER_NAME/.z2m/log/**/*.txt {}
EOF
