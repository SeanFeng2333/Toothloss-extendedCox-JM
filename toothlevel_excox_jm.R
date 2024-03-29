library(survival)
library(Matrix)
library(lme4)
library(nlme)
library(splines)
library(statmod)
library(JointModel)
library(MASS)
library(JM)
library(Rcpp)
library(here)
library(tidyverse)
library(ggridges)
library(rstanarm)

# read the tooth-level data
vadls <- read.csv("vadls_jm_toothlevel.csv", header = TRUE)

## longitudinal data
valong <- vadls

## survival data
vasurv <- vadls %>%
  dplyr::group_by(id, tooth) %>%
  mutate(basepock = maxpock[1L],
         basesmoke = smoking[1L]) %>%
  arrange(obstime) %>%
  slice(n()) %>%
  ungroup() 

## data for extended Cox model 
tdsurv <- tmerge(vasurv, vasurv, id = idtooth, endpt = event(time, tloss) )
tdsurv <- tmerge(tdsurv, vadls, id = idtooth,
                 maxpock = tdc(obstime, maxpock),
                 smoking = tdc(obstime, smoking),
                 bmi = tdc(obstime, basebmi))


# restrict patients with at least 26 teeth at baseline and add tooth type 
firstmolars <- c(3,14,19,30)
secondmolars <- c(2,15,18,31)
molars <- c(firstmolars, secondmolars)
id26teeth <- vasurv %>%
  dplyr::filter(basenumteeth > 25) %>%
  dplyr::select(id) %>%
  distinct()
vasurv <- vasurv %>% 
  dplyr::filter(id %in% id26teeth$id) %>%
  group_by(id) %>%
  mutate(newid = cur_group_id(),
         firstmolar = ifelse(tooth %in% firstmolars, 1, 0),
         secondmolar = ifelse(tooth %in% secondmolars, 1, 0),
         nonmolar = ifelse(tooth %in% molars, 0, 1))
valong <- valong %>%
  dplyr::filter(id %in% id26teeth$id) %>%
  group_by(id) %>%
  mutate(newid = cur_group_id(),
         firstmolar = ifelse(tooth %in% firstmolars, 1, 0),
         secondmolar = ifelse(tooth %in% secondmolars, 1, 0),
         nonmolar = ifelse(tooth %in% molars, 0, 1)) 
tdsurv <- tdsurv %>% 
  dplyr::filter(id %in% id26teeth$id) %>%
  group_by(id) %>%
  mutate(newid = cur_group_id(),
         firstmolar = ifelse(tooth %in% firstmolars, 1, 0),
         secondmolar = ifelse(tooth %in% secondmolars, 1, 0),
         nonmolar = ifelse(tooth %in% molars, 0, 1))



### extended Cox model
tdcox <- coxph(Surv(tstart, tstop, endpt) ~ maxpock + baseage + basebmi + basesmoke +college + firstmolar + secondmolar,
               data = tdsurv, cluster = id)

summary(tdcox)



### joint model
# first, fit longitudinal submodel
jmlong <- lme(maxpock ~ bs(obstime, degree = 3) + baseage + basebmi + smoking + college + firstmolar + secondmolar,
              random = ~ obstime | idtooth,
              data = valong,
              na.action = na.omit)
summary(jmlong)


# next, fit survival submodel
jmcox <- coxph(Surv(time, tloss) ~ baseage + basebmi + smoking +college + firstmolar + secondmolar,
               cluster = id,
               data = vasurv,
               x = TRUE)
summary(jmcox)

# finally, fit joint model (current value model)
jmtloss <- jointModel(jmlong, jmcox,
                      timeVar = "obstime",
                      method = "piecewise-PH-aGH")

summary(jmtloss)

