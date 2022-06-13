#!/bin/bash

(
    sleep 1
    xdg-open http://localhost:80 #change 'xdg-open' to 'open' for MAC
) &

sudo ssh -L 80:172.0.0.1:80 \
    -i .ssh/my_key.pem \
    ubuntu@bastion.server.com
