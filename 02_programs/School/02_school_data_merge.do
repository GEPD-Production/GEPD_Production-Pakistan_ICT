clear all

*set the paths
gl data_dir ${clone}/01_GEPD_raw_data/
gl processed_dir ${clone}/03_GEPD_processed_data/


*save some useful locals
local preamble_info_individual school_code 
local preamble_info_school school_code 
local not school_code
local not1 interview__id

***************
***************
* School File
***************
***************

********
*read in the raw school file
********
frame create school
frame change school

use "${data_dir}\\School\\EPDash.dta" 

********
*read in the school weights
********

frame create weights
frame change weights
import delimited "${data_dir}\\Sampling\\${weights_file_name}"

* rename school code
rename ${school_code_name} school_code
rename location urban_rural
gen strata=tehsil+"-"+gender

keep school_code ${strata} ${other_info} strata_prob ipw

destring school_code, replace force
destring strata_prob, replace force
duplicates drop school_code, force




******
* Merge the weights
*******
frame change school

gen school_code = school_emis_preload
*fix missing cases
replace school_code = m1s0q2_emis if school_info_correct==0


destring school_code, replace force

drop if missing(school_code)

frlink m:1 school_code, frame(weights)
frget ${strata} ${other_info} urban_rural strata_prob ipw, from(weights)


*create weight variable that is standardized
gen school_weight=1/strata_prob // school level weight

*fourth grade student level weight
egen g4_stud_count = mean(m4scq4_inpt), by(school_code)


*create collapsed school file as a temp
frame copy school school_collapse_temp
frame change school_collapse_temp

order school_code
sort school_code

* collapse to school level
ds, has(type numeric)
local numvars "`r(varlist)'"
local numvars : list numvars - not

ds, has(type string)
local stringvars "`r(varlist)'"
local stringvars : list stringvars- not

collapse (max) `numvars' (firstnm) `stringvars', by(school_code)


***************
***************
* Teacher File
***************
***************

frame create teachers
frame change teachers
********
* Addtional Cleaning may be required here to link the various modules
* We are assuming the teacher level modules (Teacher roster, Questionnaire, Pedagogy, and Content Knowledge have already been linked here)
* See Merge_Teacher_Modules code folder for help in this task if needed
********
use "${data_dir}\\School\\PAK_ICT_teacher_level.dta" 

recode m2saq3 1=2 0=1

cap drop urban_rural
cap drop public
cap drop school_weight
foreach var in $other_info {
	cap drop `var'
}
cap drop $strata

frlink m:1 school_code, frame(school_collapse_temp)
frget school_code ${strata} $other_info urban_rural  school_weight numEligible numEligible4th, from(school_collapse_temp)

*get number of 4th grade teachers for weights
egen g4_teacher_count=sum(m3saq2_4), by(school_code)
egen g1_teacher_count=sum(m3saq2_1), by(school_code)

order school_code
sort school_code

*weights
*teacher absense weights
*get number of teachers checked for absense
egen teacher_abs_count=count(m2sbq6_efft), by(school_code)
gen teacher_abs_weight=numEligible/teacher_abs_count
replace teacher_abs_weight=1 if missing(teacher_abs_weight) //fix issues where no g1 teachers listed. Can happen in very small schools

*teacher questionnaire weights
*get number of teachers checked for absense
egen teacher_quest_count=count(m3s0q1), by(school_code)
gen teacher_questionnaire_weight=numEligible4th/teacher_quest_count
replace teacher_questionnaire_weight=1 if missing(teacher_questionnaire_weight) //fix issues where no g1 teachers listed. Can happen in very small schools

*teacher content knowledge weights
*get number of teachers checked for absense
egen teacher_content_count=count(m3s0q1), by(school_code)
gen teacher_content_weight=numEligible4th/teacher_content_count
replace teacher_content_weight=1 if missing(teacher_content_weight) //fix issues where no g1 teachers listed. Can happen in very small schools

*teacher pedagogy weights
gen teacher_pedagogy_weight=numEligible4th/1 // one teacher selected
replace teacher_pedagogy_weight=1 if missing(teacher_pedagogy_weight) //fix issues where no g1 teachers listed. Can happen in very small schools


drop if missing(school_weight)

********************************************************************************
save "${processed_dir}\\School\\Confidential\\Merged\\teachers.dta" , replace
********************************************************************************



********
* Add some useful info back onto school frame for weighting
********

*collapse to school level
frame copy teachers teachers_school
frame change teachers_school

collapse g1_teacher_count g4_teacher_count, by(school_code)

frame change school
frlink m:1 school_code, frame(teachers_school)

frget g1_teacher_count g4_teacher_count, from(teachers_school)



***************
***************
* 1st Grade File
***************
***************

frame create first_grade
frame change first_grade
use "${data_dir}\\School\\ecd_assessment.dta" 



frlink m:1 interview__key interview__id, frame(school)
frget school_code ${strata} $other_info urban_rural strata school_weight m6_class_count g1_teacher_count, from(school)


order school_code
sort school_code

*weights
gen g1_class_weight=g1_teacher_count/1, // weight is the number of 1st grade streams divided by number selected (1)
replace g1_class_weight=1 if g1_class_weight<1 //fix issues where no g1 teachers listed. Can happen in very small schools

bysort school_code: gen g1_assess_count=_N
gen g1_stud_weight_temp=m6_class_count/g1_assess_count // 3 students selected from the class

gen g1_stud_weight=g1_class_weight*g1_stud_weight_temp

save "${processed_dir}\\School\\Confidential\\Merged\\first_grade_assessment.dta" , replace

***************
***************
* 4th Grade File
***************
***************

frame create fourth_grade
frame change fourth_grade
use "${data_dir}\\School\\fourth_grade_assessment.dta" 


frlink m:1 interview__key interview__id, frame(school)
frget school_code ${strata}  $other_info urban_rural strata school_weight m4scq4_inpt g4_teacher_count g4_stud_count, from(school)

order school_code
sort school_code

*weights
gen g4_class_weight=g4_teacher_count/1, // weight is the number of 4tg grade streams divided by number selected (1)
replace g4_class_weight=1 if g4_class_weight<1 //fix issues where no g4 teachers listed. Can happen in very small schools

bysort school_code: gen g4_assess_count=_N

gen g4_stud_weight_temp=g4_stud_count/g4_assess_count // max of 25 students selected from the class

gen g4_stud_weight=g4_class_weight*g4_stud_weight_temp

save "${processed_dir}\\School\\Confidential\\Merged\\fourth_grade_assessment.dta" , replace

***************
***************
* Collapse school data file to be unique at school_code level
***************
***************

frame change school

*******
* collapse to school level
*******

*drop some unneeded info
drop enumerators*

order school_code
sort school_code

* collapse to school level
ds, has(type numeric)
local numvars "`r(varlist)'"
local numvars : list numvars - not

ds, has(type string)
local stringvars "`r(varlist)'"
local stringvars : list stringvars- not




* Store variable labels:

 foreach v of var * {
	local l`v' : variable label `v'
       if `"`l`v''"' == "" {
 	local l`v' "`v'"
 	}
 }
 
 * Store value labels: 
 
label dir 
return list


local list_of_valuelables = r(names)  // specify labels you want to keep
* local list_of_valuelables =  "m7saq7 m7saq10 teacher_obs_gender"

// save the label values in labels.do file to be executed after the collapse:
label save using "${clone}/02_programs/School/labels.do", replace
// note the names of the label values for each variable that has a label value attached to it: need the variable name - value label correspodence
   local list_of_vars_w_valuelables
 * foreach var of varlist m7saq10 teacher_obs_gender m7saq7 {
   
   foreach var of varlist * {
   
   local templocal : value label `var'
   if ("`templocal'" != "") {
      local varlabel_`var' : value label `var'
      di "`var': `varlabel_`var''"
      local list_of_vars_w_valuelables "`list_of_vars_w_valuelables' `var'"
   }
}
di "`list_of_vars_w_valuelables'"




********************************************************************************
*drop labels and then reattach
label drop _all
collapse (mean) `numvars' (firstnm) `stringvars', by(school_code)

********************************************************************************



* Comment_AR: After the collpase above the variable type percision changes from byte to double 


/*
fre m1*
fre m2*
fre m3*
fre m4*
fre m5*
fre m6*
fre m7*
fre m8*
fre s1*
fre s2*
*/



/*
// Round variables to convert them from a new variable with byte precision

local lab_issue "s1_c7_2 s1_c9_3 s1_c9_1 s1_c9 s1_c8_3 s1_c8_2 s1_c8_1 s1_c8 s1_c7_3 s1_c7_2 s1_b6_3 s1_b6_2 s1_b6_1 s1_b6 s1_b5_2 s1_b5_1 s1_b4_3 s1_b4_2 s1_b4_1 s1_b4 s1_b3_4 s1_b3_3 s1_b3_1 s1_b3 s1_a2_3 s1_a2_2 s1_a2_1 s1_a2 s1_a1_3 s1_a1_2 s1_a1_1 s1_a1 s1_0_3_2 s1_0_2_2 s1_0_2_1 s1_0_1_2 s1_0_1_1"

foreach var of local lab_issue {	
replace `var' = round(`var')
}
*/


* Redefine var labels:  
  foreach v of var * {
	label var `v' `"`l`v''"'
 }
 
// Run labels.do to redefine the label values in collapsed file
do "${clone}/02_programs/School/labels.do"
// reattach the label values
foreach var of local list_of_vars_w_valuelables {
   cap label values `var' `varlabel_`var''
}


fre s1_c7_2 s1_c9_3 s1_c9_1 s1_c9 s1_c8_3 s1_c8_2 s1_c8_1 s1_c8 s1_c7_3 s1_c7_2 s1_b6_3 s1_b6_2 s1_b6_1 s1_b6 s1_b5_2 s1_b5_1 s1_b4_3 s1_b4_2 s1_b4_1 s1_b4 s1_b3_4 s1_b3_3 s1_b3_1 s1_b3 s1_a2_3 s1_a2_2 s1_a2_1 s1_a2 s1_a1_3 s1_a1_2 s1_a1_1 s1_a1 s1_0_3_2 s1_0_2_2 s1_0_2_1 s1_0_1_2 s1_0_1_1


* Fix instrument label error:
la define m1saq6a 1 "Urdu" 2 "English", modify
la define m1saq6b 1 "Urdu" 2 "English", modify

la list m1saq6a m1saq6b


save "${processed_dir}\\School\\Confidential\\Merged\\school.dta" , replace

