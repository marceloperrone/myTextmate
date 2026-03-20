#import "FileItemImage.h"
#import <TMFileReference/TMFileReference.h>

NSImage* CreateIconImageForURL (NSURL* url, BOOL isModified, BOOL isMissing, BOOL isDirectory, BOOL isSymbolicLink)
{
	NSImage* res;

	if(isMissing)
	{
		res = [NSWorkspace.sharedWorkspace iconForFileType:NSFileTypeForHFSTypeCode(kUnknownFSObjectIcon)];
	}
	else
	{
		TMFileReference* fileReference = [TMFileReference fileReferenceWithURL:url];
		res = fileReference.image;
	}

	res = [res copy];
	res.size = NSMakeSize(16, 16);

	return isModified ? [NSImage imageWithSize:res.size flipped:NO drawingHandler:^BOOL(NSRect dstRect){
		[res drawInRect:dstRect fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:0.4];
		return YES;
	}] : res;
}
