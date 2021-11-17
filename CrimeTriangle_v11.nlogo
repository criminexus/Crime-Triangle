;;-------------------------------------------------------
;; BREEDS OF AGENTS
;;create three breeds according to problem analysis triangle + another breed to manage crime events
breed [pedestrians pedestrian]    ;; potential targets
breed [guardians guardian]        ;; potential guardians
breed [offenders offender]        ;; potential offenders
breed [crimes crime]              ;; agent created when a crime starts

globals
[
  ;;Variables defined as switches:  (disabled)
  ;;  pedestrians_dynamic?
  ;;  guardians_dynamic?
  ;;  offenders_dynamic?
  ;;  chess_terrain? terrain configuration
  ;;  N_pedestrians
  ;;  N_offenders
  ;;  N_guardians

  ;;Other global variables
  N_opportunities          ;;     number of situations where offenders and pedestrians are together on same patch
  N_pedestrians_killed     ;;     number of pedestrians killed
  N_offenders_killed       ;;     number of offenders killed
  N_guardians_killed       ;;     number of guardians killed
]

;;-------------------------------------------------------
;; PROPERTIES OF AGENTS

offenders-own
[
  activity               ;;         current activity (not_considering_crime, scanning, committing_crime, )
  strength
]

pedestrians-own
[
  strength
]

guardians-own
[
  strength
]

patches-own
[
  list_breed_occupants   ;;        list with the breeds of all the agents on a patch.
]

crimes-own
[
  offender_id             ;;       index (who) of offenders involved in the crime
  pedestrian_id           ;;       index (who) of pedestrians involved in the crime
  guardian_id             ;;       index (who) of guardians involved in the crime
  list_agents_involved    ;;       list with the indices (who) of all agents involved in the crime
  status                  ;;       current phase (crime_started, crime_in_progress, crime_in_progress, crime_ended)
  result                  ;;       consequences of the crime
  result_offenders        ;;       consequences of the crime for individual offenders
  result_pedestrians      ;;       consequences of the crime for individual pedestrians
  result_guardians        ;;       consequences of the crime for individual guardians
  death_list              ;;       list of agents (who) who were killed during crime
]

;;-------------------------------------------------------
;; SET UP TERRAIN AND CREATE AGENTS
to setup

  clear-all
  reset-ticks

  ;;create simulation environment
  ifelse (chess_terrain? = true) [create_terrain_chess][create_terrain_city]

  ;;set number of agents
  ;set N_pedestrians 20
  ;set N_guardians 6
  ;set N_offenders 3

  ;;setup global variables
  set N_offenders_killed 0
  set N_pedestrians_killed 0
  set N_guardians_killed 0
  set N_opportunities 0

  set-default-shape offenders "triangle"
  set-default-shape pedestrians "circle"
  set-default-shape guardians "x"
  set-default-shape crimes "flag"

  ;;create agents
  create-pedestrians N_pedestrians
  create-guardians N_guardians
  create-offenders N_offenders

  ;;setup agents
  ask pedestrians [
    set size 0.75
    set color orange
    move-to one-of patches with [pcolor = grey]
    set strength random 10
  ]

  ask guardians [
    set size 1
    set color blue
    move-to one-of patches with [pcolor = grey]
    set strength 30
  ]

  ask offenders [
    set size 0.75
    set color magenta
    move-to one-of patches with [pcolor = grey]
    set strength random 30
    set activity "not_considering_crime"
  ]

end

;;-------------------------------------------------------
;; MAIN PROCEDURE
to go

  ;stop the simulation when there are no pedestrians or offenders left
  if (not any? pedestrians or not any? offenders) [stop]

  ;;--------------

  ask pedestrians [
    ;; this part removes pedestrians killed during crime
    ;; this part is tricky because the first condition can contain a list with a single item "[.]" and the second condition can contain a list with a single item within a list!
    ;; hence the use of ["crime_finishing"] and item 0
    ifelse (([status] of in-link-neighbors = ["crime_finishing"]) and (member? who item 0 ([death_list] of in-link-neighbors))) [
      set N_pedestrians_killed N_pedestrians_killed + 1
      die
      ][
      if (pedestrians_dynamic? = true and not any? crimes-here) [
        move_pedestrians
      ]
    ]
  ]

  ;;--------------

  ask guardians [
    ;; this part removes guardians killed during crime
    ifelse (([status] of in-link-neighbors = ["crime_finishing"]) and (member? who item 0 ([death_list] of in-link-neighbors))) [
      set N_guardians_killed N_guardians_killed + 1
      die
      ][
      if (guardians_dynamic? = true and not any? crimes-here) [
        move_guardians
      ]
    ]
  ]

  ;;--------------
  ;offender agents can have three activity status: not_considering_crime; scanning; committing_crime
  ask offenders [
    ;;Offender moves
    if (offenders_dynamic? = true) [
      if (not (any? crimes-here) and not (activity = "committing_crime")) [
        move_offenders
      ]
    ]

    (ifelse

    ;;When offender is not interested in crime, there s a chance that might look for criminal opportunities
    activity = "not_considering_crime" [
      if (random 99 < 30) [set activity "scanning"]
    ]

    ;;When the agent looks for criminal opportunities and sees a potential victim, create an agent to represent the crime event.
    (activity = "scanning") and (member? pedestrians ([breed] of turtles-here)) [
      let _offender_id who
      let _pedestrian_id [who] of one-of pedestrians-here ;; later we can change this to take the most CRAVED
      let _guardian_id [who] of guardians-here ;; all guardians are involved in the crime
      hatch-crimes 1 [
        set color red
        set status "crime_started"
        set offender_id _offender_id
        set pedestrian_id _pedestrian_id
        set guardian_id _guardian_id
        set death_list []
        set result_offenders []
        set result_pedestrians []
        set result_guardians []
      ]
      set activity "committing_crime" ;;this indicates this is the start of he crime events, new crime agents would continue to be created during the crime process
    ]

    ;;When offender is committing crime
    activity = "committing_crime" [

      ;;Updating state of offender after crime
      ;; this part removes guardians killed during crime
      ifelse (([status] of in-link-neighbors = ["crime_finishing"]) and (member? who item 0 ([death_list] of in-link-neighbors))) [
        set N_offenders_killed N_offenders_killed + 1
        die
        ][
        ;; once the crime is over the offender should go back to "not_considering_crime"
        ;; note: this block is placed above the next block so the two blocks are not executed in the same time step
        if (not member? crimes ([breed] of turtles-here)) [
          set activity "not_considering_crime"  ; the offender goes back to default mode
        ]
      ]
    ]
    )

  ]


  ;;--------------
  ;crime agents can have four status: crime_started; crime_in_progress; crime_finishing; crime ended
  ask crimes [

    (ifelse

      status = "crime_started" [
        ;;link agents involved in the crime to crime agent
        create-link-with offender offender_id
        create-link-with pedestrian pedestrian_id
        foreach guardian_id [ x -> create-link-with guardian x]
        ;show [who] of in-link-neighbors -- if we want to see which agents are linked to the crime agent

        ;;create sorted list with agents involved in the crime
        ifelse (any? guardians-here) [
          set list_agents_involved (list (list (offender offender_id)) (list (pedestrian pedestrian_id)) ((sort guardians-here)) )  ;;note: this list has three elements of different types: agent, agent and agent-set
          ][
          set list_agents_involved (list (list (offender offender_id)) (list (pedestrian pedestrian_id)))
        ]
        ;show list_agents_involved

        set status "crime_in_progress"
      ]

      status = "crime_in_progress" [

        ;;compute the crime event and determine the outcome of the crime
        set result crime_process list_agents_involved
        ;show result

        ;;update the variable indicating the consequences (death list) for each offender involved in the crime
        let list_offenders_involved item 0 list_agents_involved
        let _index_O 0
        set result_offenders item 0 result
        repeat (length list_offenders_involved) [
          if (item _index_O result_offenders = "killed")[
            set death_list lput [who] of (item _index_O list_offenders_involved) death_list ;; add id
          ]
          set _index_O _index_O + 1
        ]

        ;;update the variable indicating the the consequences (death list) for each pedestrian involved in the crime
        let list_pedestrians_involved item 1 list_agents_involved
        let _index_P 0
        set result_pedestrians item 1 result
        repeat length list_pedestrians_involved [
          if (item _index_P result_pedestrians = "killed")[
            set death_list lput [who] of (item _index_P list_pedestrians_involved) death_list ;; add id
          ]
          set _index_P _index_P + 1
        ]

        if (length result = 3)[
          ;;update the variable indicating the consequences (death list) for each agent involved in the crime
          let list_guardians_involved item 2 list_agents_involved
          let _index_G 0
          set result_guardians item 2 result
          repeat length list_guardians_involved [
            if (item _index_G result_guardians = "killed")[
              set death_list lput [who] of (item _index_G list_guardians_involved) death_list ;; add id
            ]
            set _index_G _index_G + 1
          ]
        ]

        set status "crime_finishing"
      ]


      status = "crime_finishing" [
        ;;this stage is a waiting stage while agents involved update their states
        ;;it ensures the crime agents disappear *after* the killed agents
        set status "crime_ended"
      ]


      status = "crime_ended" [
        ;ask offender offender_id [set activity "not_considering_crime" ] ;;otherwise this offender would never commit crime after the first one]
        die  ;;crime agent dies
      ])
  ]

  tick
end




;;-------------------------------------------------------
;; CRIME PROCESS
to-report crime_process [#list_involved]

  let _list_offenders_involved []
  let _list_pedestrians_involved []
  let _list_guardians_involved []

  let _list_offenders_results []
  let _list_pedestrians_results []
  let _list_guardians_results []

  let _offenders_fate "safe"
  let _pedestrians_fate "safe"
  let _guardians_fate ""

  ;;define list of agents !!caution: these are not agentsets
  set _list_offenders_involved   item 0 #list_involved
  set _list_pedestrians_involved item 1 #list_involved
  ;;if there are guardians on patch...
  if (length #list_involved = 3) [
    set _list_guardians_involved item 2 #list_involved
    set _guardians_fate "safe"
  ]

  let outcome ""

  ;;compute impact of crime on pedestrians
  let _index_P 0
  repeat length _list_pedestrians_involved [
    ifelse (random 99 < 50) [set outcome "killed"][set outcome "safe"]
    set _list_pedestrians_results lput outcome _list_pedestrians_results
    set _index_P _index_P + 1
    ]

  ;;if there are guardians too...
  if (length  #list_involved = 3) [
    ;;determine who won between guardians and offenders
    ifelse (sum([strength] of turtle-set _list_guardians_involved) > sum([strength] of turtle-set _list_offenders_involved)) [set _offenders_fate "killed"] [set _offenders_fate "safe"]
  ]

  ;;compute impact of crime on offenders
  let _index_O 0
  repeat length _list_offenders_involved [
      ifelse (length #list_involved = 3) [
        ifelse (random  99 < 50) [set outcome "killed"][set outcome "safe"]][
        set outcome "safe"]
      set _list_offenders_results lput outcome _list_offenders_results
      set _index_O _index_O + 1
    ]

  ;;compute impact of crime on guardians
  let _index_G 0
  if (length #list_involved = 3) [
    repeat length _list_guardians_involved [
      ifelse (random  99 < 50) [set outcome "killed"][set outcome "safe"]
      set _list_guardians_results lput outcome _list_guardians_results
      set _index_G _index_G + 1
    ]

  ]

  ;;create list with the impact of the crime on offenders, pedestrians and guardians and report it
  let _list_fate []
  ifelse (length #list_involved = 3) [
    set _list_fate (list _list_offenders_results _list_pedestrians_results _list_guardians_results)][
    set _list_fate (list _list_offenders_results _list_pedestrians_results)
  ]

  report _list_fate

end


;;-------------------------------------------------------
;; MOVEMENT

to-report find_possible_next_patches
  let _poptions ""
  ifelse (chess_terrain? = true) [
    set _poptions neighbors  with [not any? crimes-here]][
    set _poptions neighbors4 with [not any? crimes-here and pcolor = grey]
  ]
  report _poptions
end

to move_pedestrians
  let _next_patch_options find_possible_next_patches
  move-to one-of _next_patch_options
end

to move_offenders
  let _next_patch_options find_possible_next_patches
  move-to one-of _next_patch_options
end

to move_guardians
  let _next_patch_options find_possible_next_patches
  move-to one-of _next_patch_options
end

;;-------------------------------------------------------
;; CREATE THE TERRAIN

to create_terrain_chess
  set-patch-size 20
  ask patches with [(remainder (pxcor + pycor) 2 ) = 0 ]  [
    set pcolor white]
  ask patches with [(remainder (pxcor + pycor) 2 ) = 1 ]  [
    set pcolor grey]
end


to create_terrain_city
  set-patch-size 20
  ask patches with [((remainder (pxcor) 2 )) = 0 or ((remainder (pycor) 2 ) = 0) ]  [
    set pcolor white]
  ask patches with [((remainder (pxcor) 2 ) = 1) or ((remainder (pycor) 2 ) = 1)]  [
    set pcolor grey]

end
;;-------------------------------------------------------
@#$#@#$#@
GRAPHICS-WINDOW
400
11
1008
620
-1
-1
20.0
1
10
1
1
1
0
0
0
1
0
29
0
29
0
0
1
ticks
30.0

BUTTON
27
84
144
117
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
26
47
143
80
setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
152
47
315
80
pedestrians_dynamic?
pedestrians_dynamic?
0
1
-1000

SWITCH
151
85
314
118
guardians_dynamic?
guardians_dynamic?
0
1
-1000

SWITCH
150
123
315
156
offenders_dynamic?
offenders_dynamic?
0
1
-1000

PLOT
27
226
389
636
Number of agents alive in the simulation
ticks
Number of agents
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"offenders" 1.0 0 -13840069 true "plot count offenders" "plot count offenders"
"pedestrians" 1.0 0 -817084 true "plot count pedestrians" "plot count pedestrians"
"guardians" 1.0 0 -14070903 true "plot count guardians" "plot count guardians"

MONITOR
26
172
144
217
N_pedestrians_killed
N_pedestrians_killed
17
1
11

MONITOR
272
173
388
218
N_guardians_killed
N_guardians_killed
17
1
11

MONITOR
150
172
266
217
N_offenders_killed
N_offenders_killed
17
1
11

BUTTON
27
122
144
155
go once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
152
10
314
43
chess_terrain?
chess_terrain?
1
1
-1000

INPUTBOX
319
10
397
70
N_offenders
3.0
1
0
Number

INPUTBOX
319
72
396
132
N_guardians
60.0
1
0
Number

INPUTBOX
318
136
395
196
N_pedestrians
20.0
1
0
Number

@#$#@#$#@
## WHAT IS IT?

The code simulates interactions between three types of agents: offenders, guardians and pedestrians (potential victims). After each tick, offenders can be killed by guardians, guardians can be killed by offenders, pedestrians can be killed by offenders. Killed agents are removed from the environment. Netlogo reports the total number of agents as a function of time.

## HOW IT WORKS

The switches on the interface can be used to make a breed static or dynamic. After each tick, the dynamic agents randomly moves to one of the neighboring patches. 

Offender agents can have three activity status: 
-not_considering_crime; 
-scanning; 
-committing_crime.

When a crime event happens, the crime agent that is generated can have one of the following status: 
-crime_started; 
-crime_in_progress; 
-crime_finishing; 
-crime ended. 

The outcome of the crime is calculated using a random number generator.

## HOW TO USE IT

Specify the number of agents you want in the simulation. Press Setup to set-up the terrain and use the switches to decide which breed(s) of agents should be dynamic. Press Go to make the agents move, and watch the number of agents on the plot.

## THINGS TO NOTICE

-

## THINGS TO TRY

-


## EXTENDING THE MODEL

-

## NETLOGO FEATURES

-

## RELATED MODELS

-

## CREDITS AND REFERENCES

-
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.2.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
