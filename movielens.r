###################################################################################################################################
# BEGIN given code to create edx and validation sets
###################################################################################################################################
##########################################################
# Create edx set, validation set (final hold-out test set)
##########################################################

# Note: this process could take a couple of minutes

if(!require(tidyverse)) install.packages("tidyverse", repos = "http://cran.us.r-project.org")
if(!require(caret)) install.packages("caret", repos = "http://cran.us.r-project.org")
if(!require(data.table)) install.packages("data.table", repos = "http://cran.us.r-project.org")

library(tidyverse)
library(caret)
library(data.table)

# MovieLens 10M dataset:
# https://grouplens.org/datasets/movielens/10m/
# http://files.grouplens.org/datasets/movielens/ml-10m.zip

dl <- tempfile()
download.file("http://files.grouplens.org/datasets/movielens/ml-10m.zip", dl)

ratings <- fread(text = gsub("::", "\t", readLines(unzip(dl, "ml-10M100K/ratings.dat"))),
                 col.names = c("userId", "movieId", "rating", "timestamp"))

movies <- str_split_fixed(readLines(unzip(dl, "ml-10M100K/movies.dat")), "\\::", 3)
colnames(movies) <- c("movieId", "title", "genres")

# if using R 3.6 or earlier:
#movies <- as.data.frame(movies) %>% mutate(movieId = as.numeric(levels(movieId))[movieId],
#                                            title = as.character(title),
#                                            genres = as.character(genres))
# if using R 4.0 or later:
movies <- as.data.frame(movies) %>% mutate(movieId = as.numeric(movieId),
                                            title = as.character(title),
                                            genres = as.character(genres))


movielens <- left_join(ratings, movies, by = "movieId")

# Validation set will be 10% of MovieLens data
set.seed(1, sample.kind="Rounding") # if using R 3.5 or earlier, use `set.seed(1)`
test_index <- createDataPartition(y = movielens$rating, times = 1, p = 0.1, list = FALSE)
edx <- movielens[-test_index,]
temp <- movielens[test_index,]

# Make sure userId and movieId in validation set are also in edx set
validation <- temp %>% 
      semi_join(edx, by = "movieId") %>%
      semi_join(edx, by = "userId")

# Add rows removed from validation set back into edx set
removed <- anti_join(temp, validation)
edx <- rbind(edx, removed)

rm(dl, ratings, movies, test_index, temp, movielens, removed)
###################################################################################################################################
# END given code to create edx and validation sets
###################################################################################################################################
###################################################################################################################################
# BEGIN transformation of edx data
###################################################################################################################################

# We need to generate predictors in order to have enough information to be able
# to train an algorithm to predict movie ratings. Ratings may be affected by:
# * Genre/genres
# * Year released
# * Year/month/day rated
# * User doing the rating
# Step 1 is to mutate the edx set to add columns:
# * A 1/0 for each genre a movie is in
# * Year released
# * Year rated
# * Month rated
# * Day rated

Genres <- str_split(edx$genres, "[|]", simplify = TRUE) # produces one row per rating
Genres <- unique(Genres[Genres != ""]) # gathers all unique genre names into a single array
#edx2 <- edx
for(g in Genres) {
      x <- !is.na(str_match(edx$genres, g))
      x <- data.frame(dummy = ifelse(x, 1, 0))
      colnames(x) <- g #FIXME: there is one extra column labeled "NA"
      edx <- cbind(edx, x)
}
edx <- edx %>% select(-"NA")
