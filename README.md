# Time Series App

A Flutter mobile application for time series measurement. Supports Android and iOS.

I want to create an app for my phone.
the app is a data collection app,
the data is time series, where each point is an integer on a scale of 0-10

the application has 3 modes: management, collection and visualisation.

-- collection --
in collection mode, the application has containers, that the user choolse from, and can add or rename a container.

after choosing a container, the user can start collecting a new data series

once started, the application will start a timer, and present the user the numbers 0-10, each time the user clicks a number, a new data point is collected. the data point is (time in seconds, value)

the collection is stopped when the stop button is clicked.
the data set is saved with:
- creation time
- notes user provides after collection

the collection block has a few features:
each feature is configurable in the collection start screen.
the configurations defaults is saved according to last usage, per container.


1. assisted collection: in assisted collection the application will remind the user to collect data points, if a data point wasn't collected for a configurable dT time
the notification can be either 'beep' or short flashlight. after a notification the idle timer is reset.
if 3 consecutive notifications are ignored, the collection phase is closed

2. replay: In replay phase the user can choose a past measurement, and his target is to replay that measurment. 
 the application will present the 'next target data point' and a countdown to it: how many seconds are left from current time to the time that data point was created. 
2.1 replay interpolation: if the replayed set data points values are distant by more than 1, the application will simulate (an) interpolated data point(s) by linear interpolation
2.2 data collection is functional while in replay mode
2.3 time stretch: the user can choose to stretch the chosen set, either to fixed time In seconds, or by multiplicative value between 0.5 - 2


-- visualisation 
in visualisation there are 2 viewing modes

per data set:
the user can choose per container, any number of data sets, and present them over a graph where the horizontal axis is time, and the vertical axis is value

per collection time:
the user choose collection period and collection interval and the application presents a stacked bar graph for the collection period, per collection interval.
one stacked bar for each collection interval
the stacked bar graph is a histogram of the 'average time per value bucket' where the buckets are configurable in the management section, and defaults are 0-3, 4-5, 6-7, 8, 9-10
each bucket has different color, and the size of the stack is the value of the histogram.
in example if the data series is
(0,0) (10,2) (20,3) (30,2) (40,4) (50,5) (60,10)
the bars will show: 
0-3 bar : size proportional to 40
4-5 bar : size proportional to 20
9-10 bar : size proportional to 10

note that there can be many data sets in 1 time window, and they should be averaged
note that the data set should be linearly interpolated to present the 'assumed cuttof point' 
note that 2 different time windows have 'different sum of stacks' which should be represent in different height of the total stacked graph


-- management 
in Management section the user can create and destroy containers

the user can export and import containers




-- end of definitions v 1.1


I want you to write the application for my phone



## Getting Started

1. Ensure Flutter is installed and added to your PATH.
2. Run `flutter pub get` to fetch dependencies.
3. To run the app:
   - Android: `flutter run`
   - iOS: `flutter run`

## Project Structure
- `lib/main.dart`: App entry point
- `assets/`: Place your assets here
- `pubspec.yaml`: Project configuration
