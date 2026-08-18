function d = gridWorldDefaults(layout)
%GRIDWORLDDEFAULTS The sensor range and mission length a layout is built for.
%
%   Inputs
%     LAYOUT  the layout name
%
%   Outputs
%     D       struct with sensorRange and numPoses, the pair measured to fill
%             that layout's route while leaving the graph at or under thirteen
%             variables
%
%   Utility
%     Give three callers one definition of each layout's baseline settings, so
%     they cannot disagree about which range a measurement was taken at.
%
%   THIRTEEN IS THE OFFICE'S NUMBER AND THESE PAIRS INHERIT ITS MISTAKE.
%   It was taken for an engine property when it had only been measured on the
%   office, and the eighteen-cell sweep since found the warehouse failing at
%   ten variables while the office is fine at thirteen. So holding the
%   warehouse under thirteen does not put it "inside the regime" -- there is
%   no single number that does that across layouts. Worse, its 4.0 m range
%   was chosen to hold that count down, and raising it to 5.0 m adds three
%   variables and REDUCES the error. These pairs are kept because every
%   measurement on record was taken at them, and changing them silently would
%   invalidate the tables in datasets.makeGridWorldCase without moving a
%   single number in them. They are a baseline, not a recommendation.
%
%   WHY THIS IS ITS OWN FUNCTION AND NOT TWO NUMBERS IN A SWITCH. Three
%   callers need them and they need to agree. datasets.makeGridWorldCase
%   resolves the NaN sentinels with them; methods.gridWorldSweepPlan puts the
%   range on every row as an axis coordinate and would otherwise be writing
%   4.0 into a column whose cell was built at whatever the layout said; and
%   the app sets its pose spinner from them when the layout changes. Copied
%   into three places, the failure is silent: a sweep row labelled with one
%   range and measured at another is a wrong number with a plausible axis.
%
%       layout      sensor range   poses   variables at that pose count
%       office          5.5 m        5              13
%       corridor        5.5 m        6              10
%       warehouse       4.0 m        6              12
%
%   The counts are at seed 11 and are what datasets.makeGridWorldCase's
%   tables were measured at.
%
%   See also datasets.makeGridWorldCase, methods.gridWorldSweepPlan.

arguments
    layout (1,1) string {mustBeMember(layout, ["office","corridor","warehouse"])}
end

switch layout
    case "office"
        d = struct('sensorRange', 5.5, 'numPoses', 5);
    case "corridor"
        d = struct('sensorRange', 5.5, 'numPoses', 6);
    case "warehouse"
        d = struct('sensorRange', 4.0, 'numPoses', 6);
end
end
