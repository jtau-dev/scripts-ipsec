
N=${1:-1}
REMOTE_SERVER="'10.7.159.36 -p 2222'"
cmd="./transport_perf.sh $N ${REMOTE_SERVER}  full both p0 p0"
echo $cmd
eval $cmd

