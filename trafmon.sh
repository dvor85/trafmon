#!/bin/bash

SELF_DIR=`readlink -f "$(dirname $0)"`;
MYSQL_USER=acct
MYSQL_PASS=acct_password
MYSQL_DB=netacct
CHAIN=int2ext


function usage
{
    echo "Usage: $(basename $0) [block|unblock <ip>] [stat [ip]] [clear] [help]"
    exit 1
}

function log
{
    msg=$1
    logger -t 'trafmon' -i -p user.info "$msg"
}

function stat_month
{
    IP=$1
    mysql -B -s -u $MYSQL_USER -p$MYSQL_PASS $MYSQL_DB --execute "select SUM(input)/1024/1024/1024 from traffic where ip='$IP' and MONTH(time)=MONTH(NOW()) and ((TIME(time) > '09:00:00' and TIME(time) < '12:00:00') or (TIME(time) > '13:00:00' and TIME(time) < '18:00:00')) limit 1;" || return 1
}

function truncate_db
{
    mysql -B -s -u $MYSQL_USER -p$MYSQL_PASS $MYSQL_DB --execute "delete from traffic where TIMESTAMPDIFF(MONTH,time,NOW())>3;" || return 1
}

function get_ip_limit
{
    #Must use "NetStat" web interface http://netacct-mysql.gabrovo.com/?section=download.
    mysql -B -s -u $MYSQL_USER -p$MYSQL_PASS $MYSQL_DB --execute "select ip,input_traffic_price from users inner join users_ip on users.uid=users_ip.uid where input_traffic_price>0;" || return 1
}

function get_all_user_ip
{
    IP=$1
    mysql -B -s -u $MYSQL_USER -p$MYSQL_PASS $MYSQL_DB --execute "select ip from users_ip where uid in (select uid from users_ip where ip='$IP');" || return 1
}

function block
{
    IP=$1
    unblock $IP
    iptables -I $CHAIN -s $IP -j DROP &>/dev/null && log "BLOCK $IP" || return 1
}

function unblock
{
    IP=$1
    while iptables -D $CHAIN -s $IP -j DROP &>/dev/null; do
        log "UNBLOCK $IP"
    done;
}


function main
{
    truncate_db

    get_ip_limit | while read ip lim; do
        S=0
        for uip in `get_all_user_ip $ip`; do
            Suip=`stat_month $uip`
            [[ "x$Suip" = "xNULL" ]] && Suip=0
            S=`echo "$S+$Suip" | bc`
        done;
        res=$(echo "$S > $lim" | bc)
        [[ $res -eq 1 ]] && block $ip || unblock $ip
    done;
}

function stat_all
{
    get_ip_limit | while read ip lim; do
        S=`stat_month $ip`
        [[ "x$S" = "xNULL" ]] && S=0
        echo "$ip | $lim | $S"
    done;
}

case $1 in
    "block")
        [[ -n $2 ]] && block $2 || usage
    ;;
    "unblock")
        [[ -n $2 ]] && unblock $2 || usage
    ;;
    "stat")
        [[ -n $2 ]] && stat_month $2 || stat_all
    ;;
    "clear")
        truncate_db
    ;;
    "help")
        usage
    ;;
    *)
        [[ -n $1 ]] && usage || main
    ;;
esac

