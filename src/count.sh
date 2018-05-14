#!/bin/bash

if [ $# -ne 4 ]
then
    echo ""
    echo "Usage: $0 <hg19|mm10> <peak.file.lst> <bam.file.lst> <output prefix>"
    echo ""
    exit -1
fi

SCRIPT=$(readlink -f "$0")
BASEDIR=$(dirname "$SCRIPT")

# Activate environment
export PATH=${BASEDIR}/../bin/bin:${PATH}
source activate ${BASEDIR}/../bin/envs/atac

# CMD parameters
ATYPE=${1}
PFLST=${2}
BFLST=${3}
OP=${4}

# Concatenate peaks
rm -f ${OP}.concat.peaks
for P in `cat ${PFLST}`
do
    if [ ! -f ${P} ]
    then
	echo "Peak file does not exist:" ${P}
	exit -1
    else
	echo "Reading" ${P} ", Avg. peak width" `cat ${P} | awk '{SUM+=($3-$2);} END {print SUM/NR;}'`
	cat ${P} >> ${OP}.concat.peaks
    fi
done

# Cluster peaks
bedtools merge -i <(sort -k1,1V -k2,2n ${OP}.concat.peaks) | awk '{print $0"\tPeak"sprintf("%08d", NR);}' | gzip -c > ${OP}.clustered.peaks.gz
rm ${OP}.concat.peaks

# Remove blacklisted regions
bedtools intersect -v -a <(zcat ${OP}.clustered.peaks.gz) -b <(zcat ${BASEDIR}/../bed/wgEncodeDacMapabilityConsensusExcludable.bed.gz) | sort -k1,1V -k2,2n | uniq | grep -v "^Y" | grep -v "chrY" | gzip -c > ${OP}.clustered.peaks.gz.tmp
mv ${OP}.clustered.peaks.gz.tmp ${OP}.clustered.peaks.gz

# Check post-clustered peak width
echo "Post-clustered peak width" `zcat ${OP}.clustered.peaks.gz | awk '{SUM+=($3-$2);} END {print SUM/NR;}'`

# Count fragments in peaks
for B in `cat ${BFLST}`
do
    if [ ! -f ${B} ]
    then
	echo "BAM file does not exist:" ${B}
	exit -1
    else
	alfred count_dna -o ${OP}.count.gz -i ${OP}.clustered.peaks.gz ${B}
	SID=`zcat ${OP}.count.gz | head -n 1 | cut -f 5`
	mv ${OP}.count.gz ${OP}.${SID}.count.gz
    fi
done
rm ${OP}.clustered.peaks.gz

# Create count matrix
rm -f ${OP}.counts
for F in ${OP}.*.count.gz
do
    echo "Aggregating" ${F}
    if [ ! -f ${OP}.counts ]
    then
	zcat ${F} > ${OP}.counts
    else
	paste ${OP}.counts <(zcat ${F} | cut -f 5) > ${OP}.counts.tmp
	mv ${OP}.counts.tmp ${OP}.counts
    fi
    rm ${F}
done
gzip ${OP}.counts

# Split counts into TSS peaks and non-TSS peaks
zcat ${OP}.counts.gz | head -n 1 > ${OP}.tss.counts
bedtools intersect -wa -a <(zcat ${OP}.counts.gz | tail -n +2) -b <(zcat ${BASEDIR}/../bed/${ATYPE}.promoter.bed.gz) | sort -k1,1V -k2,2n | uniq >> ${OP}.tss.counts
zcat ${OP}.counts.gz | head -n 1 > ${OP}.notss.counts
bedtools intersect -v -wa -a <(zcat ${OP}.counts.gz | tail -n +2) -b <(zcat ${BASEDIR}/../bed/${ATYPE}.promoter.bed.gz) | sort -k1,1V -k2,2n | uniq >> ${OP}.notss.counts
gzip ${OP}.tss.counts ${OP}.notss.counts
rm ${OP}.counts.gz

# Deactivate environment
source deactivate
