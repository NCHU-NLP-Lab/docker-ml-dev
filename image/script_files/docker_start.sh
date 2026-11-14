if [ -f "already_ran" ]; then
    # pass
    echo "Already ran the Entrypoint once. Holding indefinitely for debugging.";
else
    # read ENV_VAR and create user;
    useradd -m $NAME -s /bin/bash;
    sudo adduser $NAME sudo;
    echo $NAME:$PASSWORD | chpasswd;
    # change volume owner for access promise
    if [ -d "/user_data" ]; then 
        # change HOME dir for user
        usermod -d /user_data $NAME
        cp /etc/skel/.bashrc /user_data
        cp /etc/skel/.profile /user_data
        #
        # user own /user_data
        chown -R $NAME:$NAME /user_data
    fi
fi
touch already_ran;

# Run repeat
service fail2ban start;
service ssh start;
SERVICE_HOME = '/'
if [ -d "/user_data" ]; then 
    # volume exists" 
    SERVICE_HOME = '/user_data'
fi