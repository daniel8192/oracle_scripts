#!/bin/bash
# set -x
#
#########################################################
#                                                       #
# Check for installed Software options in ORACLE_HOME   #
# MOS NOTE 948061.1                                     #
#                                                       #
#########################################################
#                                                       #
# v0.1 11/2016 Hillinger initial creation               #
# v0.2 02/2017 Hillinger add unified audit              #
#                                                       #
#########################################################

# check for ORACLE_HOME
if [ -z "${ORACLE_HOME}" ]; then
  echo "ERROR: ORACLE_HOME not set!" 1>&2
  exit 1
elif [ ! -d ${ORACLE_HOME} ]; then
  echo "Oracle Home ${ORACLE_HOME} not found!" 1>&2
  exit 1
elif [ ! -r  $ORACLE_HOME/rdbms/lib/libknlopt.a ]; then
  echo "ERROR:  $ORACLE_HOME/rdbms/lib/libknlopt.a does not exist or is not readable!" 1>&2
  exit 1
fi

# check for ar command
if ( ! which ar &>/dev/null ); then
  echo "ERROR: ar-command not found in PATH" 1>&2
  exit 1
fi

unknown_options=""
echo "---------------------------------------------------------------------------------"
echo "Installed Oracle-Software Options in ORACLE_HOME=${ORACLE_HOME}"
echo "---------------------------------------------------------------------------------"
for i in `ar -t $ORACLE_HOME/rdbms/lib/libknlopt.a`
do
  case $i in
   kzlilbac.o)
     echo "(OLS)  Oracle Label Security           ON"
   ;;
   kzlnlbac.o)
     echo "(OLS)  Oracle Label Security               OFF"
   ;;
   kzvidv.o)
     echo "(DV)   Oracle Database Vault           ON"
   ;;
   kzvndv.o)
     echo "(DV)   Oracle Database Vault               OFF"
   ;;
   xsyeolap.o)
     echo "(OLAP) Oracle OLAP                     ON"
   ;;
   xsnoolap.o)
     echo "(OLAP) Oracle OLAP                         OFF"
   ;;
   kkpoban.o)
     echo "(PART) Oracle Partitioning             ON"
   ;;
   ksnkkpo.o)
     echo "(PART) Oracle Partitioning                 OFF"
   ;;
   dmwdm.o)
     echo "(DM)   Oracle Data Mining              ON"
   ;;
   dmndm.o)
     echo "(DM)   Oracle Data Mining                  OFF"
   ;;
   kecwr.o)
     echo "(RAT)  Oracle Real Application Testing ON"
   ;;
   kecnr.o)
     echo "(RAT)  Oracle Real Application Testing     OFF"
   ;;
   kcsm.o)
     echo "(RAC)  Oracle Real Application Cluster ON"
   ;;
   ksnkcs.o)
     echo "(RAC)  Oracle Real Application Cluster     OFF"
   ;;
   kfon.o)
     echo "(ASM)  Storage Management              ON"
   ;;
   kfoff.o)
     echo "(ASM)  Storage Management                  OFF"
   ;;
   kciwcx.o)
     echo "(CTX)  Context Management Text         ON"
   ;;
   kcincx.o)
     echo "(CTX)  Context Management Text             OFF"
   ;;
   kzaiang.o)
     echo "(UNI)  Oracle Unified Auditing         ON"
     ;;
   kzanang.o)
     echo "(UNI)  Oracle Unified Auditing             OFF"
   ;;
   *)  # gather unknown option
      unknown_options="${unknown_options} $i"
   ;;
  esac
done
echo "---------------------------------------------------------------------------------"
echo "Unknown options: ${unknown_options}"

exit 0
