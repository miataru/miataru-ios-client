### A map scale UI element for the built-in iOS `MKMapView`.

As of iOS 5, the built-in `MKMapView` doesn't support showing a map scale which could
come handy if one's interested in the magnitude of distances on the map at the current
zoom level. `LXMapScaleView` is an extension to `MKMapView` to accomplish this task.

The view basically draws a ruler with labels in the appropriate units. The scale is
based on that returned by `MKMapView` for the center point latitude. You should manually
update the view each time the map view region changes (the `mapView:regionDidChangeAnimated:`
delegate method is your friend).

You can have at most one scale view installed per map view.

Needless to say, you must link your project with the MapKit and CoreLocation frameworks.


### Example:

```objc
// mymapview.h
#import <MapKit/MapKit.h>
#import "LXMapScaleView.h"

@interface MyMapViewController <MKMapViewDelegate>
{
	MKMapView* mapView;
	LXMapScaleView* mapScaleView;
}

@end


// mymapview.m
#import "mymapview.h"

@implementation MyMapViewController

- (void)viewDidLoad
{
	// you may as well perform this initialization with a XIB+appropriate IBOutlets
	mapView = [[[MKMapView alloc] initWithFrame:[UIScreen mainScreen].bounds] autorelease];
	mapView.delegate = self;
	[self.view addSubview:mapView];

	// here comes the interesting part
	// get a handle to the map scale view of our mapView (by eventually installing one first)
	mapScaleView = [LXMapScaleView mapScaleForMapView:mapView];
	
	// adjust visual settings if necessary
	mapScaleView.position = kLXMapScalePositionTopLeft;
	mapScaleView.style = kLXMapScaleStyleBar;

	// NOTE:
	// you MUST NOT add the mapScaleView yourself to the hosting map view, 
	// the LXMapScaleView does that for you
}


- (void)viewDidUnload
{
	mapView = nil;
	mapScaleView = nil;
}


- (void)mapView:(MKMapView*)aMapView regionDidChangeAnimated:(BOOL)aAnimated
{
	// the map scale will retrieve the current state of the mapView it is attached to
	// and update itself accordingly
	[mapScaleView update];
}

@end
```
