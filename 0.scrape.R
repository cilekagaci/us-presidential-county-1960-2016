library('noncensus')
library('tidyverse')
library('stringr')
library('magrittr')
library('rvest')

get_state <- function(state_fips, year) {
  print(c(year, state_fips))
  url <- sprintf('http://uselectionatlas.org/RESULTS/datagraph.php?year=%d&fips=%s&f=1&off=0&elect=0', year, state_fips)
  source_raw <- read_file(url)
  
  source <- read_html(source_raw)
  
  tables <- source %>% 
    html_nodes('.info') %>% 
    extract2(1) %>%
    html_nodes('table')
  
  rows <- list()
  if (length(tables) == 0) {
    return(list());
  }

  for (i in 1:length(tables)) {
    county_name <- tables[[i]] %>%
      html_nodes('tr td') %>% 
      extract2(1) %>% 
      html_text
    
    cells <- tables[[i]] %>%
      html_nodes('tr td') %>% 
      html_text %>% 
      extract(2:length(.)) 
    
    dfx <- data.frame(county.name = county_name,
                      candidate.name = cells[seq(1, length(cells), 4)],
                      vote.percent = cells[seq(2, length(cells), 4)],
                      vote.count = cells[seq(3, length(cells), 4)],
                      state_fips = state_fips) %>%
      mutate(vote.percent = as.numeric(vote.percent %>% str_replace_all('%', '')),
             vote.count = as.numeric(vote.count %>% str_replace_all(',', '')))
    rows[[i]] = dfx
  }
  do.call(rbind, rows)
}


get_year <- function(year) {
  df <- lapply(states$state_fips, get_state, year) %>% 
    do.call(rbind, .)
  df$year <- year
  df
}


data('counties')
states = select(counties, state, state_fips) %>%
  distinct %>%
  filter(!state %in% c('AS', 'GU', 'MP', 'PR', 'UM', 'VI'))


for (year in seq(2016, 1960, -4)) {
  df <- get_year(year)
  write_tsv(df, sprintf('data/raw/%d.tsv', year))
}
