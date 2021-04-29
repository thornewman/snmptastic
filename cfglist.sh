#!/bin/bash
#
# Configuration Tracking Lister for SNMPTASTIC
#
# Usage:
# ./cfglist          # Lists all configurations in tracking directory
# ./cfglist foo      # Lists all configurations in tracking directory with name containing "foo"
# ./cfglist foo /bar # Lists all "foo" configuration in tracking directory "/bar"
# 
#
#

config=$1
counter=0
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
        if [[ "$OSTYPE" == "linux-gnu*"* ]]; then
                date=`date -d @${epoch%%.*} +"%a %d %b %Y %r"`
        elif [[ "$OSTYPE" == "darwin*"* ]]; then
                date=`date -r @${epoch%%.*} +"%a %d %b %Y %r"`
        fi
        echo "$file ( $date )"
        ((counter=$counter+1))
done

echo "$counter Configurations Listed"
##
## End of File
##
