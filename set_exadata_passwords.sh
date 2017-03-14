#!/bin/bash
#########################################################
#                                                       #
# change all passwords of one exadata                   #
#                                                       #
#########################################################
#                                                       #
# v0.1 11/2016 Hillinger start script                   #
#                                                       #
# possible expantions                                   #
# change grup password                                  #
#                                                       #
#########################################################

#set -x

#read password from stdin 
read -p "Enter password:" password1
read -p "Enter password again:" password2
if [ "$password1" = "$password2" ] && [ ${#password1} -ge 8 ]
then
  password="$password1"
  unset password1 password2
else
  echo "Passowrd missmatch or less then 8 chars" 1>&2
  exit 1
fi

#find exadata prefix
db="$(hostname -s)"
cel="$(getent hosts $(cut -d \" -f2 /etc/oracle/cell/network-config/cellip.ora |cut -d \; -f1 |tail -1) |awk '{ print $2 } ')"
exa_prefix="$(for i in `seq 1 ${#db}` ; do if [ "${db:$i-1:1}" = "${cel:$i-1:1}" ]; then printf "${db:$i-1:1}" ; else break; fi; done)"
unset db cel

#collect information about the exadata components
dbnodes="$(olsnodes)"
cells="$(cut -d \" -f2 /etc/oracle/cell/network-config/cellip.ora |cut -d \; -f1|xargs -n1 getent hosts|awk '{print $2}' |cut -d '-' -f 1)"
switches="$(ibswitches |grep $exa_prefix |awk '{print $10}')"
pdus="$(getent hosts ${exa_prefix}{sw-pdu,p,-pdu}{a,b}{0,1,}{0,1,} |awk '{print $2}'|sort -u)"

#define user which should be changed
dbnode_users="root oracle"
cell_users="root celladmin cellmonitor"
ilom_users="root oemuser MSUser"
ib_users="root nm2user ilom-admin ilom-operator"
asm_users="sys asmsnmp"
pdu_user="admin"

#env
ssh_opts="-o StrictHostKeyChecking=no"

echo "GRUB password will not be changed! Not needed!"

#on all computing nodes
for i in $dbnodes
do
  echo "changing passwords on $i "
  ssh $ssh_opts $i "for user in $dbnode_users 
    do
      echo -en \"\t\t\${user}\"
      echo \"\${user}:${password}\" | chpasswd -c SHA512
      if [ $? -eq 0 ]
      then
        echo \"... SUCCESS\"
      else
        echo -e \"... \e[1;31mERROR\e[0m\"
      fi
    done"
done

#on all cells
for i in $cells
do
  echo "changing passwords on $i "
  ssh $ssh_opts $i "for user in $cell_users
    do
      echo -en \"\t\t\${user}\"
      echo \"\${user}:${password}\" | chpasswd -c SHA512
      if [ $? -eq 0 ]
      then
        echo \"... SUCCESS\"
      else
        echo -e \"... \e[1;31mERROR\e[0m\"
      fi
    done"
done


# change password on iloms
for i in $dbnodes $cells
do
  echo "changing ilom passwords on $i "
  ssh $ssh_opts $i "for user in $ilom_users
    do
      echo -en \"\t\t\${user}\"
      ipmitool sunoem cli \"set -script /SP/users/\${user} password=${password}
${password}
\" &>/dev/null
      if [ $? -eq 0 ]
      then
        echo \"... SUCCESS\"
      else
        echo -e \"... \e[1;31mERROR\e[0m\"
      fi
    done"
done

#change asm password
echo "changing asm passwords "
su - grid -c "for user in $asm_users
do
  echo -en \"\t\t\${user}\"
  echo -e \"alter user \${user} identified by \"${password}\";\" |sqlplus -S / as sysasm|grep -q \"User altered.\"
  if [ $? -eq 0 ]
  then
    echo \"... SUCCESS\"
  else
    echo -e \"... \e[1;31mERROR\e[0m\"
  fi
done"

#change password on infiniband switches
for i in $switches
do
  echo "changing ib passwords on $i"
  ssh $ssh_opts $i "for user in $ib_users
    do
      echo -en \"\t\t\${user}\"
      echo \"\${user}:${password}\" | chpasswd -c SHA512
      if [ $? -eq 0 ]
      then
        echo \"... SUCCESS\"
      else
        echo -e \"... \e[1;31mERROR\e[0m\"
      fi
    done"
done

#change pdu passwords
for i in $pdus
do
  echo "changing pdu passwords on $i"
  curl https://${i} &>/dev/null
  if [ $? -eq 7 ] #pdu version prior 2
  then
    for x in {1..3}
    do
      read -p "Enter current pdu password: " old_password
      if ( ! curl "http://${i}/getUser.cgi?user=${pdu_user}&pass=${old_password}" 2>/dev/null |grep -q "<title>Login</title>" )
      then
        curl "http://${i}/addUserPass.cgi?US1=${pdu_user}&PA1=${password}&PO1=2" 2>/dev/null |grep -q "<title>Net Configuration / Firmware Update / Module Info </title>"
        if [ $? -eq 0 ]
        then
          echo "... SUCCESS"
        else
          echo -e "... \e[1;31mERROR\e[0m"
        fi
        curl "http://${i}/logout.cgi?logout=Logout" &>/dev/null
        break;
      else
        echo "not able to login to PDU"
        [ $x -eq 3 ] && echo -e "... \e[1;31mERROR\e[0m"
      fi
    done
  else # pdu version 2 or higher
    for x in {1..3}
    do
      read -p "Enter current pdu password: " old_password
      if ( ! curl --insecure -X POST -d "User=${pdu_user}&Pass=${old_password}" https://${i}/Login.cgi 2>/dev/null |grep -q "url=Login.htm" )
      then
        curl --insecure -X POST -d "HttpU1=${pdu_user}&HttpP1=${password}&HttpP1R=${password}&HttpR1=2" https://${i}/Http_Access.cgi 2>/dev/null|grep -q "url=Http_Access.htm"
        if [ $? -eq 0 ]
        then
          echo "... SUCCESS"
        else
          echo -e "... \e[1;31mERROR\e[0m"
        fi
        curl --insecure -X POST https://${i}/Logout.cgi &>/dev/null
        break;
      else
        echo "not able to login to PDU" 
        [ $x -eq 3 ] && echo -e "... \e[1;31mERROR\e[0m"
      fi
    done
  fi #end if version
done