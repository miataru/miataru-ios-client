//
//  LXMapScaleView.h
//
//  Created by Tamas Lustyik on 2012.01.09..
//  Copyright (c) 2012 LKXF. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>


/**
 * \enum LXMapScaleStyle
 * \brief Map scale style
 */
typedef enum
{
	kLXMapScaleStyleBar,				//!< Simple bar with black and white units
	kLXMapScaleStyleAlternatingBar,		//!< Vertically divided bar with black and white units
	kLXMapScaleStyleTapeMeasure			//!< Tape measure-like segment
} LXMapScaleStyle;


/**
 * \enum LXMapScalePosition
 * \brief Map scale position
 */
typedef enum
{
	kLXMapScalePositionTopLeft,			//!< Top left corner
	kLXMapScalePositionTop,				//!< Centered on top
	kLXMapScalePositionTopRight,		//!< Top right corner
	kLXMapScalePositionBottomLeft,		//!< Bottom left corner
	kLXMapScalePositionBottom,			//!< Centered at bottom
	kLXMapScalePositionBottomRight		//!< Bottom right corner
} LXMapScalePosition;


/**
 * \class LXMapScaleView
 * \brief Map scale UI element for the built-in iOS MKMapView.
 *
 * As of iOS 5, the built-in MKMapView doesn't support showing a map scale which could
 * come handy if one's interested in the magnitude of distances on the map at the current
 * zoom level. LXMapScaleView is an extension to MKMapView to accomplish this task.
 *
 * The view basically draws a ruler with labels in the appropriate units. The scale is
 * based on that returned by MKMapView for the center point latitude. You should manually
 * update the view each time the map view region changes (the mapView:regionDidChangeAnimated:
 * delegate method is your friend).
 *
 * You can have at most one scale view installed per map view.
 *
 * Needless to say, you must link your project with the MapKit and CoreLocation frameworks.
 *
 * Note: Owing to the characteristics of the Mercator projection used by the map view,
 * the scale view may show different values at different latitudes without changing the
 * zoom level. This is not a bug. :)
 */
@interface LXMapScaleView : UIView

//! Sets the style of the map scale. Default is kLXMapScaleStyleBar.
@property (readwrite, nonatomic, assign) LXMapScaleStyle style;

//! Sets whether to use the metric or the imperial/customary scale. Default is YES (metric).
@property (readwrite, nonatomic, assign, getter = isMetric) BOOL metric;

//! Sets the position of the scale relative to the hosting map view. Default is kLXMapScalePositionBottomLeft.
@property (readwrite, nonatomic, assign) LXMapScalePosition position;

//! Sets the padding between the scale and the edges of the map view. Default is (10,10,10,10).
@property (readwrite, nonatomic, assign) UIEdgeInsets padding;

//! Sets the maximum width for the view. Default is 160 pixels.
@property (readwrite, nonatomic, assign) CGFloat maxWidth;


/**
 * \brief Returns the map scale view instance for the given map view.
 *
 * If the map view doesn't already have a map scale then the method first installs one,
 * otherwise it returns a handle to the scale view. Each map view can have
 * at most one scale installed.
 * \param aMapView The map view for which the scale view is to be returned.
 * \return A handle to the scale view. (Note that ownership is not passed!)
 */
+ (LXMapScaleView*)mapScaleForMapView:(MKMapView*)aMapView;


/**
 * \brief Updates the map scale.
 *
 * You must call this method every time the map view region changes, typically from
 * the map view's -[MKMapViewDelegate mapView:regionDidChangeAnimated:] delegate method.
 */
- (void)update;

@end
