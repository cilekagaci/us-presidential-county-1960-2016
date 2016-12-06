library('Hmisc')
library('stringr')
library('tidyverse')
library('magrittr')
library('choroplethrMaps')

elections <- data.frame(
  rbind(
    c(1960, 'Kennedy', 'Nixon', 'D', 'first'),
    c(1964, 'Johnson', 'Goldwater', 'D', 'first'),
    c(1968, 'Humphrey', 'Nixon', 'R', 'first'),
    c(1972, 'McGovern', 'Nixon', 'R', 'second'),
    c(1976, 'Carter', 'Ford', 'D', 'first'),
    c(1980, 'Carter', 'Reagan', 'R', 'first'),
    c(1984, 'Mondale', 'Reagan', 'R', 'first'),
    c(1988, 'Dukakis', 'Bush', 'R', 'first'),
    c(1992, 'Clinton', 'Bush', 'D', 'first'),
    c(1996, 'Clinton', 'Dole', 'D', 'second'),
    c(2000, 'Gore', 'Bush', 'R', 'first'),
    c(2004, 'Kerry', 'Bush', 'R', 'second'),
    c(2008, 'Obama', 'McCain', 'D', 'first'),
    c(2012, 'Obama', 'Romney', 'D', 'second'),
    c(2016, 'Clinton', 'Trump', 'R', 'first')
  )
) %>% set_names(c('year',
                  'democratic.candidate', 
                  'republican.candidate', 
                  'winning.party', 
                  'term')) %>%
  mutate(year = as.numeric(as.character(year)))
dems <- unique(elections$democratic.candidate)
reps <- unique(elections$republican.candidate)


years <- list()
for (year in seq(1960, 2016, 4)) {
  years[[length(years) + 1]] <- read_tsv(sprintf('data/raw/%d.tsv', year))
}


df = do.call(rbind, years) %>% 
  mutate(county.name = str_to_lower(county.name)) %>%
  rename(state.fips.character = state_fips) %>% 
  # Filter out Virginia and Alaska, see details in the documentation.
  filter(state.fips.character != '02', state.fips.character != '51') %>%
  group_by(state.fips.character, county.name, year, candidate.name) %>%
  # Independent cities and counties may have the same name. In these cases
  # the cities are given at the bottom of the page. Update name accordingly.
  mutate(new.county.name = ifelse(row_number() == 1, county.name, paste0(county.name, ' city'))) %>%
  ungroup %>%
  mutate(county.name = new.county.name) %>%
  select(-new.county.name)

data(county.regions)  # From the package choroplethrMaps

# For 2016, use ME and MA from 
ma_me_2016_raw <- read_csv('https://github.com/tonmcg/County_Level_Election_Results_12-16/raw/master/US_County_Level_Presidential_Results_08-16.csv') 
ma_me_2016 = ma_me_2016_raw%>%
  gather(key, vote.count, matches('_2008|_2012|_2016')) %>%
  tidyr::extract(key, into = c('party', 'year'), '^([[:alnum:]]*)_([0-9]+)', convert = TRUE) %>%
  filter(party != 'total') %>%
  filter(grepl('^(23|25)', fips_code)) %>%
  transmute(candidate.name = ifelse(party == 'dem', 'Clinton',
                           ifelse(party == 'gop', 'Trump', 'Other')),
            county.fips = fips_code,
            year,
            vote.count) %>%
  group_by(year, county.fips) %>%
  mutate(vote.percent = 100 * vote.count / sum(vote.count)) %>%
  inner_join(county.regions, by = c("county.fips" = "county.fips.character")) %>%
  ungroup %>%
  transmute(county.name, candidate.name, vote.percent, vote.count, state.fips.character, year)

df = bind_rows(df %>% filter(!(state.fips.character %in% c('23', '25'))), ma_me_2016)

# Fix non-matching names for three large cities.
df[df$county.name == 'dade' & df$state.fips.character == '12', ]$county.name <- 'miami-dade'
county.regions[county.regions$county.fips.character == '29510', ]$county.name <- 'st. louis city'
county.regions[county.regions$county.fips.character == '24510', ]$county.name <- 'baltimore city'

df[df$county.name == 'shannon' & df$state.fips.character == '46', ]$county.name <- 'oglala lakota'
county.regions[county.regions$county.fips.character == '46113', ]$county.name <- 'oglala lakota'

df %<>% inner_join(county.regions) %>% 
  group_by(county.fips.character) %>%
  # Number of elections each county was observed in
  mutate(obs.count = n_distinct(year)) %>%
  # Eliminate counties that are observed in less than 10 elections
  filter(obs.count >= 10) %>%
  ungroup %>%
  # Merges anything that's not Dem. or Rep. into 'other' category.
  mutate(party = ifelse(candidate.name %in% dems, 'D', 
                        ifelse(candidate.name %in% reps, 'R',
                               'O'))) %>%
  group_by(county.name,
           county.fips.character, 
           state.fips.character,
           year, 
           region,
           state.name,
           state.abb,
           obs.count,
           party) %>%
  summarise(vote.percent = sum(vote.percent),
            vote.count = sum(vote.count)) %>%
  group_by(county.fips.character, year) %>%
  mutate(county.total.count = sum(vote.count)) %>%
  filter(county.total.count > 0) %>%
  ungroup


national.totals <- df %>%
  group_by(year, party) %>%
  summarise(national.party.count = sum(vote.count)) %>%
  group_by(year) %>%
  mutate(national.count = sum(national.party.count),
         national.party.percent = 100 * national.party.count / national.count)

counties_1960_2016 <- df %>% 
  inner_join(national.totals) %>%
  inner_join(elections) %>%
  transmute(year, 
            county.fips = county.fips.character, 
            map.id = region, 
            state.fips = state.fips.character, 
            county.name, 
            state.name, 
            state.abb, 
            election.count = obs.count,
            party,
            vote.percent,
            vote.count,
            county.total.count,
            national.party.count,
            national.party.percent,
            national.count,
            is.national.winner = winning.party == party)

write_tsv(counties_1960_2016, path = 'data/processed/us-presidential-counties-1960-2016.tsv')

