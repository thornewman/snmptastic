#!/bin/bash
#
# Configuration Tracking Lister for SNMPTASTIC
#
# Usage:
# ./cfglist           # Lists all configurations in tracking directory
# ./cfglist foo       # Lists all configurations in tracking directory with name containin "foo"
# ./cfglist foo /bar  # Lists all "foo" configuration in tracking directory "/bar"
#
#

config=$1
tracking="tracking"
if [ -z "$2" ]; then
        tracking="tracking"
else
        tracking=$2
fi

pat='\.+([0-9]+)$'
for f in $tracking/* ; do
        if [[ "`echo $f | cut -d/ -f2`" != *"$config"* ]]; then
                continue
        fi
        if [[ "$f" == *"-state-file" ]]; then
                continue
        fi
        file=${f#*_}
        [[ $file =~ $pat ]]
        epoch=${BASH_REMATCH[1]}
        date=`date -d @${epoch%%.*} +%c`
        echo "$file ( $date )"

done

##
## End of File
##
