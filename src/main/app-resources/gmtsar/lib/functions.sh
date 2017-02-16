#!/bin/bash


set -x
# source the ciop functions (e.g. ciop-log)
source ${ciop_job_include}

# define the exit codes
SUCCESS=0
ERR_DEM=10
ERR_AUX=20
ERR_DOR=30
ERR_MASTERFILE=40
ERR_SLAVEFILE=50
ERR_CEOS=60

# add a trap to exit gracefully
function cleanExit () {

  local retval=$?
  local msg=""
  
  case "${retval}" in
    $SUCCESS)		msg="Processing successfully concluded";;
    $ERR_DEM)		msg="Failed to retrieve auxiliary data";;
    $ERR_AUX)		msg="Failed to retrieve auxiliary data";;
    $ERR_DOR)		msg="Failed to retrieve orbital data";;
    $ERR_MASTERFILE)	msg="Master not retrieved";;
    $ERR_SLAVEFILE)	msg="Slave not retrieved";;
    $ERR_CEOS)	msg="CEOS not extracted";;
    *)			msg="Unknown error";;
  esac

  [ "${retval}" != "0" ] && ciop-log "ERROR" "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"

  exit ${retval}

}

trap cleanExit EXIT

function set_env() {

  export OS=`uname -p`
  export GMTHOME=/usr
  export NETCDFHOME=/usr
  export GMTSARHOME=/usr/local/GMTSAR
  export GMTSAR=${GMTSARHOME}/gmtsar
  export ENVIPRE=${GMTSARHOME}/ENVISAT_preproc
  export PATH=${GMTSAR}/bin:${GMTSAR}/csh:${GMTSARHOME}/preproc/bin:${GMTSARHOME}/ENVISAT_preproc/bin/:${GMTSARHOME}/ENVISAT_preproc/csh:${PATH}

  # create environment
  mkdir -p ${TMPDIR}/runtime/raw ${TMPDIR}/runtime/topo ${TMPDIR}/runtime/log ${TMPDIR}/runtime/intf &> /dev/null
  mkdir -p ${TMPDIR}/aux/ENVI/ASA_INS
  mkdir -p ${TMPDIR}/aux/ENVI/Doris

  export ORBITS=${TMPDIR}/aux

}

function main() {

  while read joborder_ref
  do
    
    ciop-log "INFO" "retrieving joborder ${joborder_ref}"
    joborder=$( ciop-copy -O ${TMPDIR} ${joborder_ref} ) 

    ciop-log "INFO" "Retrieving DEM"
    demfile=$( cat ${joborder} | grep "^dem=" | cut -d "=" -f 2- )

    ciop-copy -O ${TMPDIR}/runtime/topo ${demfile}
    [ "$?" != "0" ] && return ${ERR_NODEM}

    ciop-log "INFO" "copying the orbital data"
    for  in $( cat ${joborder} | sort -u | grep "^.or=" | cut -d "=" -f 2- )
    do
      enclosure=$( opensearch-client ${doris} enclosure )
      ciop-copy -O ${TMPDIR}/aux/ENVI/Doris ${enclosure}
      [ "$?" != "0" ] && exit ${ERR_DOR}
    done
	 
    ciop-log "INFO" "copying ASAR auxiliary data"
    for aux in $( cat ${joborder} | sort -u | grep "^aux=" | cut -d "=" -f 2- )
    do
      enclosure=$( opensearch-client ${aux} enclosure )
      ciop-copy -O ${TMPDIR}/aux/ENVI/ASA_INS ${enclosure}
      [ "$?" != "0" ] && exit ${ERR_AUX}
    done
	
    # create the list of ASA_INS_AX
    ls ${TMPDIR}/aux/ENVI/ASA_INS/ASA_INS* | sed 's#.*/\(.*\)#\1#g' > ${TMPDIR}/aux/ENVI/ASA_INS/list

    # get the references to master and slave
    master=$( cat ${joborder} | grep "^master=" | cut -d "=" -f 2- )
    slave=$( cat ${joborder} | grep "^slave=" | cut -d "=" -f 2- )

    cd ${TMPDIR}/runtime/raw
 
    # Get the master
    ciop-log "INFO" "retrieving the master from $master"
    master_ref=$( opensearch-client "${master}" enclosure | tail -1 )
    master=$( ciop-copy -O ${TMPDIR}/runtime/raw ${master} )
	
    [ -z "${master}" ] && exit ${ERR_MASTERFILE}

    [[ ${master} == *CEOS* ]] && {
      # ERS2 in CEOS format
      tar --extract --file=${master} -O DAT_01.001 > master.dat
      tar --extract --file=${master} -O LEA_01.001 > master.ldr
      [ ! -e ${TMPDIR}/runtime/raw/master.dat ] && exit ${ERR_CEOS}
      [ ! -e ${TMPDIR}/runtime/raw/master.ldr ] && exit ${ERR_CEOS}
    } || {
      # ENVISAT ASAR in N1 format
      ln -s ${master} master.baq
    }

    ciop-log "INFO" "retrieving the slave from $slave"
    slave=$( opensearch-client "$slave" enclosure | tail -1 )
    slave=$( ciop-copy -O ${TMPDIR}/runtime/raw $slave )
	
    [ -z "${slave}" ] && exit ${ERR_SLAVEFILE}

    [[ ${slave} == *CEOS* ]] && {	
      tar --extract --file=${slave} -O DAT_01.001 > ${TMPDIR}/runtime/raw/slave.dat
      tar --extract --file=${slave} -O LEA_01.001 > ${TMPDIR}/runtime/raw/slave.ldr
      flag="ers"
    } || { 	
      # ENVISAT ASAR in N1 format
      ln -s ${slave} ${TMPDIR}/runtime/raw/slave.baq
      flag="envi"
    }

    result=$( echo "${master}_${slave}" | sed 's#.*/\(.*\)\.N1_.*/\(.*\)\.N1#\1_\2#g' )

    ciop-log "INFO" "starting GMTSAR with $result"
    csh ${_CIOP_APPLICATION_PATH}/gmtsar/libexec/run_${flag}.csh & #> $TMPDIR/runtime/${result}_envi.log &
    wait ${!}			

    # publish results and logs
    ciop-log "INFO" "publishing log files"
    ciop-publish -m ${TMPDIR}/runtime/${result}_${flag}.log
	
    ciop-log "INFO" "result packaging"
    mydir=$( ls ${TMPDIR}/runtime/intf/ | sed 's#.*/\(.*\)#\1#g' )

    ciop-log "DEBUG" "outputfolder is: ${TMPDIR}/runtime/intf + $mydir"

    cd ${TMPDIR}/runtime/intf/$mydir

    #creates the tiff files
    for mygrd in $( ls *ll.grd );
    do
      gdal_translate ${mygrd} $( echo $mygrd | sed 's#\.grd#.tiff#g' )
    done
	
    for mygrd in $( ls *.grd )
    do 
      gzip -9 ${mygrd}
    done
        
    cd ${TMPDIR}/runtime/intf

    ciop-log "INFO" "publishing results"
    for myext in png ps gz tiff
    do
      ciop-publish -b ${TMPDIR}/runtime/intf -m ${mydir}/*.$myext
    done
	
    ciop-log "INFO" "cleanup"
	
    [ -d "${TMPDIR}" ] && {
      rm -fr ${TMPDIR}/runtime/raw/*
      rm -fr ${TMPDIR}/runtime/intf/*
    }	

  done

}
