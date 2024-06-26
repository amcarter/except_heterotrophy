##==============================================================================
## Script for autotrophy duration 
## Code author: J.R. Blaszczak
## Last Edited: April 17, 2024
##
## Changed NEP to P:R as the metric by which we are quantifying autotrophy
## Added NEP Figure back in
##==============================================================================

## Load packages
lapply(c("plyr","dplyr","ggplot2","cowplot","lubridate",
         "tidyverse","data.table"), require, character.only=T)

## import most up-to-date dataset
dat <- readRDS("../../data_356rivers/high_quality_daily_metabolism_with_SP_covariates.rds")
df <- dat[,c("site_name","date","GPP","ER")]
df <- na.omit(df)

## split to list by site
df_list <- split(df, df$site_name)

###########################################
## Extract events and duration of events
#############################################
duration_calc <- function(df_site){

  d <- df_site[,c("site_name","date","GPP","ER")]
  d$PR <- d$GPP/abs(d$ER)
  d$NEP <- d$GPP - abs(d$ER)

  # First calc time difference and split to segments to avoid NA days
  d$diff_time <- NA
  d$diff_time[1] <- 0
  
  for(i in 2:nrow(d)){
    d$diff_time[i] = difftime(time1 = d$date[i], time2 = d$date[(i-1)], units="days")
  }
  
  d$diff_time <- as.character(as.numeric(d$diff_time))
  d$seq <- NA
  d$seq[1] <- 1
  
  for(i in 2:nrow(d)){
    if(d$diff_time[i] %in% c("1")){
      d$seq[i] = d$seq[(i-1)]
    } else{
      d$seq[i] = d$seq[(i-1)]+1
    }
  }
  
  lseq <- split(d, as.factor(d$seq))
  
  
  events_calc <- function(z, t) {
    zz <- z %>% 
      #add id for different periods/events
      mutate(PR_above = PR > t, id = data.table::rleid(PR_above)) %>% 
      # keep only periods with autotrophy
      filter(PR_above) %>%
      # for each period/event, get its duration & magnitude
      group_by(id) %>%
      summarise(event_duration = difftime(last(date), first(date), units = "days"),
                start_date = first(date),
                end_date = last(date),
                PR_mean = mean(PR),
                NEP_mean = mean(NEP))
    
    zz[nrow(zz)+1,] <- NA
    
    return(zz)
  }
  
  event_above1 <- ldply(lapply(lseq, function(x) events_calc(x, 1)), data.frame);event_above1$PR_thresh <- 1
  
    ## subset
  events_df <- event_above1[,c("event_duration","start_date","end_date","PR_mean","NEP_mean")]
  events_df$site_name <- d$site_name[1]
  events_df <- na.omit(events_df)
  
  return(events_df)
  
}


auto_events <- lapply(df_list, function(x) duration_calc(x))
auto_df <- ldply(auto_events, data.frame)
## check event duration
auto_df[which(auto_df$event_duration < 0),]

## Add 1 to event duration
auto_df$event_duration <- auto_df$event_duration+1
auto_df$event_dur <- as.numeric(auto_df$event_duration)
head(auto_df);tail(auto_df)

## Visualize
ggplot(auto_df, aes(event_dur, fill=PR_thresh))+
  geom_histogram(binwidth = 1)+
  theme_bw()

#check PR_mean
auto_df[which(auto_df$PR_mean > 50),] ## crazy high PR values - maybe use NEP instead
#histogram
ggplot(auto_df, aes(PR_mean))+
  geom_histogram(binwidth = 1)+
  scale_x_continuous(trans = "log")+
  theme_bw()


## save
saveRDS(auto_df, "../../data_356rivers/autotrophic_event_duration_means.rds")

#############################################
## Calculations and figures for results
#############################################
auto_df <- readRDS("../../data_356rivers/autotrophic_event_duration_means.rds")

## 1 ## What % of rivers experienced at least one autotrophic event
length(levels(as.factor(auto_df$site_name))) # 212 sites
length(levels(as.factor(df$site_name))) # 223 sites
212/223 #95%

## 2 ## what percentage of days are autotrophic
sum(auto_df$event_dur) #46,042
sum(auto_df$event_dur)/nrow(df) #19%

## 3 ## Number of events per year
# Compare mean +/- events per year between 1-3 days and 1-3 months
#first compare if any events cross years
auto_df$year_start <- year(auto_df$start_date)
auto_df$year_end <- year(auto_df$end_date)
auto_df$year_diff <- auto_df$year_end - auto_df$year_start
nrow(auto_df[which(auto_df$year_diff > 0),]) ## only 18 sites; will attribute to start year
#classify if an event is 1-3 days or 1-3 months
duration_days<-c(1, 3, 7, 14, 30, 90)
auto_df$duration_cat <- factor(findInterval(auto_df$event_dur,duration_days))
auto_df$duration_length <- revalue(auto_df$duration_cat, c("1" = "1 day to 3 days",
                                              "2" = "3 days to 1 week",
                                              "3" = "1 week to 2 weeks",
                                              "4" = "2 weeks to 1 month",
                                              "5" = "1 month to 3 months"))

## visualize
ggplot(auto_df, aes(duration_length))+
  geom_bar(alpha=0.4, color="black", position="identity")+
  theme_bw()+
  theme(panel.grid.major.y = element_line(color="gray85"),
        axis.title = element_text(size=14),
        axis.text.x = element_text(size=14, angle=35, hjust = 1),
        axis.text.y = element_text(size=14),
        legend.position = "top")+
  labs(x="Event duration", y="Number of events")

#group by site and year and calculate mean duration_length category per year per site
length_site_year <- auto_df %>%
  group_by(site_name, year_start,duration_length) %>%
  count()
#expand this to include 0 for each length and site and year
#only include 1-3 days and 1-3 months
length(levels(as.factor(auto_df$site_name))) #212
levels(as.factor(length_site_year$year_start)) #2008-2016
# Create a site-year index
length_site_year$site_year <- paste(length_site_year$site_name,
                                    length_site_year$year_start,sep="_")
# For every site-year index, create a data frame with both 1-3 days and 1-3 months
events <- NULL
events <- as.data.frame(rep(levels(as.factor(length_site_year$site_year)),2))
colnames(events) <- "site_year"
events$duration_length <- c(rep(levels(as.factor(auto_df$duration_length))[1], nrow(events)/2),
                                rep(levels(as.factor(auto_df$duration_length))[5], nrow(events)/2))
head(events); tail(events)
#merge
combined <- merge(events, length_site_year,
                  by = c("site_year","duration_length"),
                  all = TRUE)
#change all NA n values to 0
combined[is.na(combined$n),]$n <- 0
#summarize
mean_sd_length_year <- combined %>%
  group_by(duration_length) %>%
  summarize(mean = mean(n), sd = sd(n))
# 1 to 3 days = 9.8 +/- 8.4 events/year
# 1 to 3 months = 0.04 +/- 0.21 events/year



## 4 ## Month of onset and termination
auto_df$onset_month <- month(auto_df$start_date)
auto_df$end_month <- month(auto_df$end_date)

#all
ggplot(auto_df, aes(as.factor(onset_month)))+
  geom_bar(fill="#010D26", alpha=0.4, color="black")+
  geom_bar(aes(end_month), fill="#4CBFBB", alpha=0.5, color="black")+
  labs(x="Month", y="Number of Events",title = "Onset Month = grey, End Month = teal")+
  facet_wrap(~as.factor(duration_length), ncol=1, scales = "free_y")+
  theme_bw()+
  theme(panel.grid.major.y = element_line(color="gray85"),
        title = element_text(size=8),
        axis.title = element_text(size=12),
        axis.text.x = element_text(size=12),
        axis.text.y = element_text(size=12),
        strip.background = element_rect(fill="white", color = "black"))

## 5 ## Magnitude of Mean P:R during events

ggplot(auto_df, aes(event_dur, PR_mean, group = event_dur))+
  geom_boxplot()+
  scale_y_continuous(trans = "log", breaks = c(1,3,10,30,100,1000,5000))+
  geom_hline(yintercept = 1)+
  theme_bw(base_size = 14)+
  labs(x = "Event Duration (days)", y = "Mean P:R")

ggplot(auto_df, aes(event_dur, NEP_mean, group = event_dur))+
  geom_boxplot()+
  theme_bw(base_size = 14)+
  labs(x = "Event Duration (days)", y = expression('Mean NEP (g '*~O[2]~ m^-2~d^-1*')'))

# End of script.
