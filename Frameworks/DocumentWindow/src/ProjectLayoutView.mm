#import "ProjectLayoutView.h"
#import <OakAppKit/OakUIConstructionFunctions.h>

@interface ProjectLayoutView ()
@property (nonatomic) NSMutableArray* myConstraints;
@end

@implementation ProjectLayoutView
- (id)initWithFrame:(NSRect)aRect
{
	if(self = [super initWithFrame:aRect])
	{
		_myConstraints = [NSMutableArray array];
	}
	return self;
}

- (NSView*)replaceView:(NSView*)oldView withView:(NSView*)newView
{
	if(newView == oldView)
		return oldView;

	[oldView removeFromSuperview];
	if(newView)
		OakAddAutoLayoutViewsToSuperview(@[ newView ], self);

	[self setNeedsUpdateConstraints:YES];
	return newView;
}

- (void)setDocumentView:(NSView*)aDocumentView { _documentView = [self replaceView:_documentView withView:aDocumentView]; }

#ifndef CONSTRAINT
#define CONSTRAINT(str, align) [_myConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:str options:align metrics:nil views:views]]
#endif

- (void)updateConstraints
{
	[self removeConstraints:_myConstraints];
	[_myConstraints removeAllObjects];
	[super updateConstraints];

	if(!_documentView)
		return;

	NSDictionary* views = @{
		@"documentView": _documentView,
	};

	CONSTRAINT(@"V:|[documentView]|", 0);
	CONSTRAINT(@"H:|[documentView]|", 0);

	[self addConstraints:_myConstraints];
}

#undef CONSTRAINT

- (BOOL)mouseDownCanMoveWindow
{
	return NO;
}

- (void)performClose:(id)sender
{
	if([self.window.delegate respondsToSelector:@selector(performClose:)])
		[self.window.delegate performSelector:@selector(performClose:) withObject:sender];
	else
		NSBeep();
}
@end
