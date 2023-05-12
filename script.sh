#来自于@coolapk 嘟嘟司机(scene 开发者)

#内存占用率清理

#内存占用达到设定值时，会回收闲置的内存。

#可能会回收几百兆，也可能时几兆。

#默认设定值为80%。

limit='80'

function M(){

	all=`/data/adb/magisk/busybox free -m | grep "Mem" | awk '{print $2}'`	use=`/data/adb/magisk/busybox free -m | grep "Mem" | awk '{print $3}'`

	echo $(($use*100/$all))

}

function mod_description(){

local file="$MODPATH/module.prop"

local text="$1"

test ! -f "$file" && return 0

sed -i "/^description=/c description=[ $(date '+%F %T') ]，$text" "$file"

}

function notification_simulation(){

local title="${2}"

local text="${1}"

if test "$(pm list package | grep -w 'com.google.android.ext.services' )" != "" ;then

	cmd notification allow_assistant 'com.google.android.ext.services/android.ext.services.notification.Assistant'

fi

#local word_count="`echo "${text}" | wc -c`"

#test "${word_count}" -gt "375" && text='文字超出限制，请尽量控制在375个字符！'

	test -z "${title}" && title='10007'

	test -z "${text}" && text='您未给出任何信息'

su -lp 2000 -c "cmd notification post -S messaging --conversation '${title}' --message '${title}':'${text}' 'Tag' '$(echo $RANDOM)' " >/dev/null 2>&1

}

if test "$(M)" -le "$limit" ;then

	echo "剩余内存$(M)%"

	echo "内存充裕！"

	#notification_simulation "剩余内存: $(M)% ，内存充裕！" "内存管理优化模块"

	exit 0

fi

notification_simulation "剩余内存$(M)% ，开始回收内存！" "内存管理优化模块"

free_old=`/data/adb/magisk/busybox free -m | grep "Mem" | awk '{print $3}'`

#清空缓存

echo '3' > /proc/sys/vm/drop_caches

if test -f '/proc/sys/vm/extra_free_kbytes' ;then

	modify_path='/proc/sys/vm/extra_free_kbytes'

	friendly=true

elif test -f '/proc/sys/vm/min_free_kbytes' ;then

	modify_path='/proc/sys/vm/min_free_kbytes'

else

	echo '搞不定，你这内核不支持！'

	return 1

fi

min_free_kbytes=`cat $modify_path`

setprop ro.key.compact_memory $min_free_kbytes || resetprop ro.key.compact_memory $min_free_kbytes

MemTotalStr=`cat /proc/meminfo | grep MemTotal`

MemTotal=${MemTotalStr:16:8}

MemMemFreeStr=`cat /proc/meminfo | grep MemFree`

MemMemFree=${MemMemFreeStr:16:8}

SwapFreeStr=`cat /proc/meminfo | grep SwapFree`

SwapFree=${SwapFreeStr:16:8}

if test "$friendly" = "true" ;then

	TargetRecycle=$(($MemTotal / 100 * 55))

else

	TargetRecycle=$(($MemTotal / 100 * 26))

fi

# 如果可用内存大于目标可用内存大小，则不需要回收了

if test $MemMemFree -gt $TargetRecycle ;then

	echo '内存充足，不需要操作！'

else

	# 计算需要回收多少内存

	RecyclingSize=$(($TargetRecycle - $MemMemFree))

	# 计算回收这些内存需要消耗的SWAP容量

	SwapRequire=$(($RecyclingSize / 100 * 130))

	# 如果没有足够的Swap容量可以回收这些内存

	# 则只拿Swap剩余容量的50%来回收内存

	if test $SwapFree -lt $SwapRequire ;then

		RecyclingSize=$(($SwapFree / 100 * 50))

	fi

	# 最后计算出最终要回收的内存大小

	TargetRecycle=$(($RecyclingSize + $MemMemFree))

	if test $RecyclingSize != "" -a $RecyclingSize -gt 0 ; then

		echo $TargetRecycle > $modify_path

	sleep_time=$(($RecyclingSize / 1024 / 60 + 2))

		while test $sleep_time -gt 0 

		do

		sync

			sleep 1

			MemMemFreeStr=`cat /proc/meminfo | grep MemFree`

			MemMemFree=${MemMemFreeStr:16:8}

			test "$(($TargetRecycle - $MemMemFree))" -lt "100" && break

			SwapFreeStr=`cat /proc/meminfo | grep SwapFree`

			SwapFree=${SwapFreeStr:16:8}

			test $SwapFree -lt 100 && break

			sleep_time=$(($sleep_time - 1))

		done

		echo $(getprop ro.key.compact_memory) > $modify_path

		sync

	else

		echo '操作失败，计算容量出错!'

	fi

fi

free_new=`/data/adb/magisk/busybox free -m | grep "Mem" | awk '{print $3}'`

echo 1 > /proc/sys/vm/compact_memory

mod_description "本次内存已回收 [ $(($free_old - $free_new)) M ]。"

notification_simulation "$(date '+%F %T')，本次内存已回收 [ $(($free_old - $free_new)) M ]。" "内存管理优化模块"
