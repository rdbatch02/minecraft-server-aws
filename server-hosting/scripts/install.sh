#!/bin/sh

# Note: Arguments to this script 
#  1: string - S3 bucket for your backup save files (required)
#  2: true|false - whether to use Satisfactory Experimental build (optional, default false)
EFS_FS_ID=$1
TIMEZONE=America/New_York

timedatectl set-timezone $TIMEZONE

sudo mkdir /mc-data
sudo sudo mount -t efs $EFS_FS_ID:/ /mc-data

amazon-linux-extras install docker -y
service docker start
usermod -a -G docker ec2-user
usermod -a -G docker $USER
systemctl enable docker

wget https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) 
sudo mv docker-compose-$(uname -s)-$(uname -m) /usr/local/bin/docker-compose
sudo chmod -v +x /usr/local/bin/docker-compose


# enable auto shutdown: https://github.com/feydan/satisfactory-tools/tree/main/shutdown
cat << 'EOF' > /home/ec2-user/auto-shutdown.sh
#!/bin/sh

shutdownIdleMinutes=30
idleCheckFrequencySeconds=1

isIdle=0
while [ $isIdle -le 0 ]; do
    isIdle=1
    iterations=$((60 / $idleCheckFrequencySeconds * $shutdownIdleMinutes))
    while [ $iterations -gt 0 ]; do
        sleep $idleCheckFrequencySeconds
        connectionBytes=$(ss -lu | grep 777 | awk -F ' ' '{s+=$2} END {print s}')
        if [ ! -z $connectionBytes ] && [ $connectionBytes -gt 0 ]; then
            isIdle=0
        fi
        if [ $isIdle -le 0 ] && [ $(($iterations % 21)) -eq 0 ]; then
           echo "Activity detected, resetting shutdown timer to $shutdownIdleMinutes minutes."
           break
        fi
        iterations=$(($iterations-1))
    done
done

echo "No activity detected for $shutdownIdleMinutes minutes, shutting down."
sudo shutdown -h now
EOF
chmod +x /home/ec2-user/auto-shutdown.sh
chown ec2-user:ec2-user /home/ec2-user/auto-shutdown.sh

cat << 'EOF' > /etc/systemd/system/auto-shutdown.service
[Unit]
Description=Auto shutdown if no one is playing Satisfactory
After=syslog.target network.target nss-lookup.target network-online.target

[Service]
Environment="LD_LIBRARY_PATH=./linux64"
ExecStart=/home/ec2-user/auto-shutdown.sh
User=ec2-user
Group=ec2-user
StandardOutput=journal
Restart=on-failure
KillSignal=SIGINT
WorkingDirectory=/home/ec2-user

[Install]
WantedBy=multi-user.target
EOF
systemctl enable auto-shutdown
systemctl start auto-shutdown

dd if=/dev/zero of=/swap bs=1M count=1024
chmod 0600 /swap
mkswap /swap
swapon -a /swap

mkdir -p /home/ec2-user/mc-server
cp docker-compose.yml /home/ec2-user/mc-server
chown -R ec2-user:ec2-user /home/ec2-user/mc-server


# enable as server so it stays up and start: https://satisfactory.fandom.com/wiki/Dedicated_servers/Running_as_a_Service
cat << EOF > /etc/systemd/system/minecraft.service
[Unit]
Description=Minecraft dedicated server
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=ec2-user
Group=ec2-user
WorkingDirectory=/home/ec2-user/mc-server
ExecStart=/usr/local/bin/docker-compose -f /home/ec2-user/mc-server/docker-compose.yml up --remove-orphans
ExecStop=/usr/local/bin/docker-compose -f /home/ec2-user/mc-server/docker-compose.yml down

[Install]
WantedBy=multi-user.target
EOF
systemctl enable minecraft
systemctl start minecraft