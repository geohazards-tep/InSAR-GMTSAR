
# define the exit codes
SUCCESS=0
ERR_JOBORDER=10

# add a trap to exit gracefully
function cleanExit () {

  local retval=$?
  local msg=""

  case "${retval}" in
    ${SUCCESS}) msg="Processing successfully concluded";;
    *) msg="Unknown error";;
  esac

  [ "$retval" != "0" ] && ciop-log "ERROR" "Error $retval - $msg, processing aborted" || ciop-log "INFO" "$msg"
  exit $retval

}
trap cleanExit EXIT

function main() {

  demfile=$( ciop-browseresults -u -r ${CIOP_WF_RUN_ID} -j node_dem | tr -d '\n\r' )

  ciop-log "INFO" "retrieving input from node_dem [${demfile}]"

  for input in $( ciop-browseresults -u -r ${CIOP_WF_RUN_ID} -j node_aux)
  do 
    
    # get the joborder 
    basefile=$( basename ${input} )
    [ ${basefile:0:8} == "joborder" ] && {
  
      joborder="$( ciop-copy -O ${TMPDIR} ${input} )"
      [ ! -e ${joborder} ] && return ${ERR_JOBORDER}

      # add the reference to the DEM 
      echo "dem=${demfile}" >> ${joborder}

      # publish the joborder file
      ciop-publish ${joborder}
    }

done

}
