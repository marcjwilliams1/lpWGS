library(QDNAseq)
library(methods)
library(dplyr)
library(argparse)
library(stringr)

parser <- ArgumentParser(description = "Parse arguments for QDNAseq analysis")
parser$add_argument('--binsize', type = 'double',
                    help="Binsize for QDNAseq run", default = 500)
parser$add_argument('--bamfiles', type = 'character',
                    help="List of bam files to process", default = NULL, nargs = "+")
parser$add_argument('--plotdir', type = 'character',
                    help="Plotting directory", default = NULL)
parser$add_argument('--Rdata', type = 'character',
                    help="Rdata file", default = NULL)
parser$add_argument('--segmentfile', type = 'character',
                    help="Text file for segments", default = NULL)
parser$add_argument('--pipelinedirectory', type = 'character',
                    help="Pipeline directory", default = NULL)
parser$add_argument('--filter', type = 'character',nargs = "+",
                    help="Text file for segments", default = NULL)
args <- parser$parse_args()

source(paste0(args$pipelinedirectory, "/scripts/blacklist.R"))
#outdir <- dirname(args$Rdata)

#directory to store plots
#plotdir <- paste0(args$plotdir, "binsize", as.numeric(binsize))
plotdir <- args$plotdir
print(plotdir)

print(paste0("Number of bam files: ", length(args$bamfiles)))

if (dir.exists(plotdir) == FALSE){
  dir.create(plotdir, recursive = T)
}

args$filter <- paste0(gsub(",", "[0-9]+|", args$filter), "[0-9]+")
print(args$filter)
print(str_detect(args$bamfiles, args$filter))

args$bamfiles <- args$bamfiles[str_detect(args$bamfiles, args$filter)]
print(args$bamfiles)

basenames <- basename(args$bamfiles)
basenames <- sub(sprintf('[\\.]?%s$', "bam"), '', basenames)
bamnames <- c()
bamnames <- basenames
#for (i in basenames){
#    x <-strsplit(i, "-")[[1]]
#    bamnames <- c(bamnames, x[length(x)])
#}
print(bamnames)

#download bin annotations
bins <- getBinAnnotations(binSize = as.numeric(args$binsize))
binsnew <- bins

#remove bins in the following regions
regions <- cbind(c(6, 4, 17), c(28500001, 69200001, 43900000), c(33500000, 69300000, 44100001))
binsnew$blacklist <- calculateBlacklistByRegions(binsnew, regions)

bins@data <- left_join(bins@data, binsnew@data,
                       by = c("chromosome", "start", "end", "bases", "gc", "mappability", "residual", "use")) %>%
             mutate(blacklist = blacklist.x,
               blacklist = ifelse(blacklist.y > 0, blacklist.y, blacklist)) %>%
            select(-blacklist.x, -blacklist.y)

#load sequencing data
readCounts <- binReadCounts(bins, bamfiles=args$bamfiles, bamnames = bamnames, pairedEnds = TRUE)

#plot raw readcounts
pdf(paste(plotdir,"/","raw_profile",".pdf",sep=""),7,4)
plot(readCounts, logTransform=FALSE, ylim=c(-10, 50),main=paste("Raw Profile ",sep=""))
highlightFilters(readCounts, logTransform=FALSE,residual=TRUE, blacklist=TRUE)
dev.off()

#apply filters and plot median read counts per bin as a function of GC content and mappability
readCountsFiltered <- applyFilters(readCounts, residual=TRUE, blacklist=TRUE)
pdf(paste(plotdir,"/","isobar",".pdf",sep=""),7,4)
isobarPlot(readCountsFiltered)
dev.off()

#Estimate the correction for GC content and mappability, and make a plot for the relationship between the
#observed standard deviation in the data and its read depth
readCountsFiltered <- estimateCorrection(readCountsFiltered)
pdf(paste(plotdir,"/","noise",".pdf",sep=""),7,4)
noisePlot(readCountsFiltered)
dev.off()

#apply the correction for GC content and mappability which we then normalize, smooth outliers, calculate segmentation
#and plot the copy number profile
copyNumbers <- correctBins(readCountsFiltered)
copyNumbersNormalized <- normalizeBins(copyNumbers)
copyNumbersSmooth <- smoothOutlierBins(copyNumbersNormalized)

pdf(paste(plotdir,"/","copy_number_profile",".pdf",sep=""),7,4)
plot(copyNumbersSmooth, ylim=c(-2,2))
dev.off()

copyNumbersSegmented <- segmentBins(copyNumbersSmooth)
print("bins segmented")
copyNumbersSegmented <- normalizeSegmentedBins(copyNumbersSegmented)

pdf(paste(plotdir,"/","segments",".pdf",sep=""),7,4)
plot(copyNumbersSegmented, ylim=c(-2,2), gaincol = "firebrick3", losscol = "dodgerblue3", delcol="dodgerblue4", ampcol = "firebrick4")
dev.off()

copyNumbersCalled <- callBins(copyNumbersSegmented)
pdf(paste(plotdir,"/","copy_numbercalls",".pdf",sep=""),7,4)
plot(copyNumbersCalled, ylim=c(-2,2), gaincol = "firebrick3", losscol = "dodgerblue3", delcol="dodgerblue4", ampcol = "firebrick4")
dev.off()

output <- list(readCounts = readCounts,
               readCountsFiltered = readCountsFiltered,
               copyNumbers = copyNumbers,
               copyNumbersNormalized = copyNumbersNormalized,
               copyNumbersSmooth = copyNumbersSmooth,
               copyNumbersSegmented = copyNumbersSegmented,
               copyNumbersCalled = copyNumbersCalled)
saveRDS(output, file = args$Rdata)

exportBins(copyNumbersSmooth, file=args$segmentfile)

pdf(paste(plotdir,"/","frequencyplot",".pdf",sep=""),7,4)
frequencyPlot(copyNumbersCalled, gaincol = "firebrick3", losscol = "dodgerblue3", delcol="dodgerblue4", ampcol = "firebrick4")
dev.off()
