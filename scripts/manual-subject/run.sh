#!/bin/zsh
# run.sh <tag> <imagePath> <press> <liftSpec> [intensity]
S=${0:A:h}; tag=$1; img=$2; press=$3; spec=$4; inten=$5
in=$S/in/$tag; out=$S/out/$tag
rm -rf $in $out; mkdir -p $in $out
ln -s $img $in/${img:t}
env HT_EVAL_MAXDIM=6000 HT_EVAL_PNG=1 HT_EVAL_PRESS=$press HT_EVAL_LIFT=$spec HT_EVAL_MASK_DUMP=$out ${inten:+HT_EVAL_INTENSITY=$inten} \
  $S/bin/eval $in - $out/m.csv all $out > $out/log.txt 2>&1
RC=$?
echo "$tag rc=$RC $(grep -h 'press mask\|usable\|note' $out/log.txt | tr '\n' ' ')"
