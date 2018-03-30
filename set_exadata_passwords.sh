#!/bin/bash
###########################################################
#                                                         #
# change all passwords of one exadata                     #
#                                                         #
###########################################################
#                                                         #
# v0.1 11/2016 Hillinger start script                     #
# v0.2 03/2018 Hillinger add options and bugfix chpasswd	#
#                                                         #
###########################################################

function usage () {
echo -e "Usage: `basename $0` [options]
-e <exaprefix> if not specified, the script tries to determinate it automatically. i.e. exa1
-d passwords changed only on dbnodes
-s passwords changed only on storage cells
-i passwords changed only on infiniband switches
-c passwords changed only on ILOMs
-a passwords changed only on ASM
-p passwords changed only on PDUs
-h print this help message"
}

if [ -n "$1" ]; then
  while getopts :he:dsicap: OPT 2>/dev/null
  do
    case $OPT in
      e)
      OPT_e_SET=1
      OPT_e="$OPTARG"
      ;;
      d)
      OPT_d_SET=1
      ;;
      s)
      OPT_s_SET=1
      ;;
      i)
      OPT_i_SET=1
      ;;
      c)
      OPT_c_SET=1
      ;;
      a)
      OPT_a_SET=1
      ;;
      p)
      OPT_p_SET=1
      ;;
      h)
      usage
      exit 0
      ;;
      *)
      OPT_error_SET=1
      OPT_error=$OPTARG$OPT_error
      ;;
    esac
  done
fi

if [ -n "$OPT_error_SET" ]; then
  usage
  echo "wrong options $OPT_error"
  exit 1
fi

#read password from stdin
read -sp "Enter password:" password1
echo
read -sp "Enter password again:" password2
echo
if [ "$password1" = "$password2" ] && [ ${#password1} -ge 8 ]; then
  password="$password1"
  unset password1 password2
else
  echo "Passowrd missmatch or less then 8 chars" 1>&2
  exit 1
fi

#set exadata prefix
if [ -n "$OPT_e_SET" ]; then
  exa_prefix="$OPT_e"
else
  db="$(hostname -s)"
  cel="$(getent hosts $(cut -d \" -f2 /etc/oracle/cell/network-config/cellip.ora |cut -d \; -f1 |tail -1) |awk '{ print $2 } ')"
  exa_prefix="$(for i in `seq 1 ${#db}` ; do if [ "${db:$i-1:1}" = "${cel:$i-1:1}" ]; then printf "${db:$i-1:1}" ; else break; fi; done)"
  unset db cel
fi

#collect information about the exadata components
dbnodes="$(olsnodes)"
cells="$(cut -d \" -f2 /etc/oracle/cell/network-config/cellip.ora |cut -d \; -f1|xargs -n1 getent hosts|awk '{print $2}' |cut -d '-' -f 1)"
switches="$(ibswitches |grep "$exa_prefix" |awk '{print $10}')"
pdus="$(getent hosts ${exa_prefix}{sw-pdu,p,-pdu}{a,b}{0,1,}{0,1,} |awk '{print $2}'|sort -u)"

#define user which should be changed
dbnode_users="root oracle"
cell_users="root celladmin cellmonitor"
ilom_users="root oemuser MSUser"
ib_users="root nm2user ilom-admin ilom-operator"
asm_users="sys asmsnmp"
pdu_user="admin"

if [ -z "$OPT_d_SET$OPT_s_SET$OPT_i_SET$OPT_c_SET$OPT_a_SET$OPT_p_SET" ]; then
  # no dedicated option is specified --> change passwords on all components
  OPT_d_SET=1
  OPT_s_SET=1
  OPT_i_SET=1
  OPT_c_SET=1
  OPT_a_SET=1
  OPT_p_SET=1
  echo "GRUB password will not be changed! Not needed!"
fi

#env
ssh_opts="-o StrictHostKeyChecking=no"

#computing nodes
if [ -n "$OPT_d_SET" ];then
  for i in $dbnodes ; do
    echo "changing passwords on $i "
    ssh $ssh_opts $i "for user in $dbnode_users ; do
      echo -en \"\t\t\${user}\"
      echo \"\${user}:${password}\" | chpasswd -c SHA512
      if [ $? -eq 0 ]; then
        echo \"... SUCCESS\"
      else
        echo -e \"... \e[1;31mERROR\e[0m\"
      fi
      done"
  done
fi

#storage cells
if [ -n "$OPT_s_SET" ];then
  for i in $cells ; do
    echo "changing passwords on $i "
    ssh $ssh_opts $i "for user in $cell_users ; do
      echo -en \"\t\t\${user}\"
      echo \"\${user}:${password}\" | chpasswd -c SHA512
      if [ $? -eq 0 ]; then
        echo \"... SUCCESS\"
      else
        echo -e \"... \e[1;31mERROR\e[0m\"
      fi
      done"
  done
fi

# infiniband switches
if [ -n "$OPT_i_SET" ];then
  for i in $switches ; do
    echo "changing ib passwords on $i"
    ssh $ssh_opts $i "for user in $ib_users ; do
      echo -en \"\t\t\${user}\"
      #echo \"\${user}:${password}\" | chpasswd -c SHA512
      #workaround for bug in chpasswd
      echo \"${password}\"|spsh set /SP/users/root password=\"${password}\" &>/dev/null
      if [ $? -eq 0 ]; then
        echo \"... SUCCESS\"
      else
        echo -e \"... \e[1;31mERROR\e[0m\"
      fi
      done"
  done
fi

# iloms
if [ -n "$OPT_c_SET" ]; then
  for i in $dbnodes $cells; do
    echo "changing ilom passwords on $i "
    ssh $ssh_opts $i "for user in $ilom_users ; do
      echo -en \"\t\t\${user}\"
      ipmitool sunoem cli \"set -script /SP/users/\${user} password=${password}
${password}
\" &>/dev/null
      if [ $? -eq 0 ]; then
        echo \"... SUCCESS\"
      else
        echo -e \"... \e[1;31mERROR\e[0m\"
      fi
      done"
  done
fi

# asm
if [ -n "$OPT_a_SET" ]; then
  echo "changing asm passwords "
  su - grid -c "for user in $asm_users ; do
    echo -en \"\t\t\${user}\"
    echo -e \"alter user \${user} identified by \"${password}\";\" |sqlplus -S / as sysasm|grep -q \"User altered.\"
    if [ $? -eq 0 ]; then
      echo \"... SUCCESS\"
    else
      echo -e \"... \e[1;31mERROR\e[0m\"
    fi
    done"
fi

# pdu
if [ -n "$OPT_p_SET" ]; then
  for i in $pdus ; do
    echo "changing pdu passwords on $i"
    curl https://${i} &>/dev/null
    if [ $? -eq 7 ]; then #pdu version prior 2
      for x in {1..3} ; do
        read -sp "Enter current pdu password: " old_password
        if ( ! curl "http://${i}/getUser.cgi?user=${pdu_user}&pass=${old_password}" 2>/dev/null |grep -q "<title>Login</title>" ); then
          curl "http://${i}/addUserPass.cgi?US1=${pdu_user}&PA1=${password}&PO1=2" 2>/dev/null |grep -q "<title>Net Configuration / Firmware Update / Module Info </title>"
          if [ $? -eq 0 ]; then
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
      for x in {1..3} ; do
        read -sp "Enter current pdu password: " old_password
        if ( ! curl --insecure -X POST -d "User=${pdu_user}&Pass=${old_password}" https://${i}/Login.cgi 2>/dev/null |grep -q "url=Login.htm" ); then
          curl --insecure -X POST -d "HttpU1=${pdu_user}&HttpP1=${password}&HttpP1R=${password}&HttpR1=2" https://${i}/Http_Access.cgi 2>/dev/null|grep -q "url=Http_Access.htm"
          if [ $? -eq 0 ]; then
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
fi
