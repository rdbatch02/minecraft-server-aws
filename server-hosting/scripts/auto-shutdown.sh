#!/bin/sh

shutdownIdleMinutes=30
idleCheckFrequencySeconds=1

isIdle=0
while [ $isIdle -le 0 ]; do
    isIdle=1
    iterations=$((60 / $idleCheckFrequencySeconds * $shutdownIdleMinutes))
    while [ $iterations -gt 0 ]; do
        sleep $idleCheckFrequencySeconds
        container_name=mc-server
        c_pid=$(docker container inspect -f "{{.State.Pid}}" $container_name)
        activeConnections=$(nsenter -t $c_pid -n netstat -anp | grep 25565 | grep ESTABLISHED | wc -l)
        if [ ! -z $activeConnections ] && [ $activeConnections -gt 0 ]; then
            echo "Active Connections: $activeConnections"
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

/bin/sh -c 'if [ ! -z $activeConnections ] && [ $activeConnections -gt 0 ]; then echo "true"; fi'