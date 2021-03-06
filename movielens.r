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
memory.limit(32000) #unnecessary on large or non-Windows machines
if(!require(lubridate)) install.packages("lubridate", repos = "http://cran.us.r-project.org")
if(!require(rpart)) install.packages("rpart", repos = "http://cran.us.r-project.org")

library(lubridate)
library(rpart)

#standard RMSE function
RMSE <- function(y, y_hat){
    sqrt(mean((y - y_hat)^2))
}

set.seed(2, sample.kind="Rounding") # if using R 3.5 or earlier, use `set.seed(2)`

#Further carve out a training and test set (80% training, 20% test) for algorithm and data exploration
test_index <- createDataPartition(y = edx$rating, times = 1, p = 0.2, list = FALSE)
train <- edx[-test_index,]
temp <- edx[test_index,]
test <- temp %>% 
    semi_join(train, by = "movieId") %>%
    semi_join(train, by = "userId")

# Add rows removed from test set back into train set
removed <- anti_join(temp, test)
train <- rbind(train, removed)
rm(removed)

# Release year, and year, month, day, week rated may be relevant for predicting ratings.
# The genres column may not be convenient for analysis. Convert it into an essentially binary 1 or 0 for
# each listed genre in case that affects users' ratings of movies.
wrangle <- function(ratings) {
    pattern <- "\\((\\d{4})\\)$"
    ratings <- ratings %>% mutate(releaseyear = as.numeric(str_match(title, pattern)[,2]),
                           year = year(as_datetime(timestamp)),
                           month = month(as_datetime(timestamp)),
                           day = day(as_datetime(timestamp)),
                           week = as.numeric(round_date(as_datetime(timestamp),unit="week"))) %>%
#                          movieId = factor(movieId),
#                          userId = factor(userId),
#                          rating = factor(rating)) %>%
                           select(-title) %>%
                           select(-timestamp)

    Genres <- str_split(ratings$genres, "[|]", simplify = TRUE) # produces one row per rating
    Genres <- sort(unique(Genres[Genres != "" & Genres != "(no genres listed)"])) # gathers all unique genre names into a single array
    print(Genres)
    for(g in Genres) {
        x <- !is.na(str_extract(ratings$genres, g))
        x <- data.frame(dummy = ifelse(x, 1, 0))
        colnames(x) <- str_remove(g,"-")
        ratings <- cbind(ratings, x)
    }
    ratings <- ratings %>% select(-genres)
    return(ratings)
}
train <- wrangle(train)
test <- wrangle(test)

#train() function is taking too much memory/time on this dataset. I wrote functions to tune by cp and minsplit manually.
rpart_predict <- function(cp, train, test) {
    library(rpart)
    RMSE <- function(y, y_hat){
        sqrt(mean((y - y_hat)^2))
    }
    fit <- rpart(rating ~ ., data=train, control=rpart.control(cp = cp, maxsurrogate=0))
    print(fit)
    return(RMSE(test$rating,predict(fit, newdata=test))) 
}

rpart_predict2 <- function(minsplit, train, test) {
    library(rpart)
    RMSE <- function(y, y_hat){
        sqrt(mean((y - y_hat)^2))
    }
    fit <- rpart(rating ~ ., data=train, control=rpart.control(minsplit = minsplit, cp=0, maxsurrogate=0))
    print(fit)
    return(RMSE(test$rating,predict(fit, newdata=test))) 
}

#rpart gives a Variable Importance list with how much each factor affects the response. For relatively
#large values of cp the tree is also small enough to plot.

fit <- rpart(rating ~ ., data=train, control=rpart.control(cp = .0025, maxsurrogate=0))
plot(fit, margin = 0.1)
text(fit, cex = 0.75)
print(fit$variable.importance)

#rpart is fairly memory efficient so I can tune it in parallel to some degree.
library(parallel)
cl <- makeCluster(3)
tune3 <- c(100000,50000,20000,10000,5000,2000,1000,500,200)
rtree_tune3 <- parSapplyLB(cl, tune3, rpart_predict2, train, test)
plot(tune3, rtree_tune3, type="b")
stopCluster(cl)

#Best minsplit is 500, though the results are not great. Plot the variable importance.
fit <- rpart(rating ~ ., data=train, control=rpart.control(cp = 0,minsplit = 500, maxsurrogate=0))
print(fit$variable.importance)
barplot(fit$variable.importance, las=2)

#least squares predictions
mu_predict <- function(train, test) {
    mu <- mean(train$rating)
    y_hat <- (test$rating*0 + mu)
    return(RMSE(test$rating, y_hat))
}

user_predict <- function(train, test) {
    mu <- mean(train$rating)
    user_effects <- train %>% group_by(userId) %>% summarize(mean = mean(rating-mu))
    user_effects <- left_join(select(test, userId), user_effects, by="userId")
    y_hat <- mu + user_effects$mean
    y_hat[is.na(y_hat) == TRUE] <- mu
    return(RMSE(test$rating, y_hat))
}
user_movie_predict <- function(train, test) {
    mu <- mean(train$rating)
    user_effects <- train %>% group_by(userId) %>%
                              summarize(u_effect = mean(rating-mu))
    movie_effects <- train %>% left_join(user_effects, by="userId") %>%
                               group_by(movieId) %>%
                               summarize(m_effect = mean(rating-mu-u_effect))
    y_hat <- test %>% left_join(user_effects, by="userId") %>% 
                      left_join(movie_effects, by="movieId") %>%
                      mutate(y_hat = mu+u_effect+m_effect) %>%
                      pull(y_hat)
    return(RMSE(test$rating, y_hat))
}
user_movie_effects_penalized_predict <- function(lambda1, lambda2, train, test) {
    library(dplyr)
    mu <- mean(train$rating)
    user_effects <- train %>% group_by(userId) %>%
                              summarize(u_effect = sum(rating-mu)/(n()+lambda1))
    movie_effects <- train %>% left_join(user_effects, by="userId") %>%
                               group_by(movieId) %>%
                               summarize(m_effect = sum(rating-mu-u_effect)/(n()+lambda2))
    y_hat <- test %>% left_join(user_effects, by="userId") %>% 
                      left_join(movie_effects, by="movieId") %>%
                      mutate(y_hat = mu+u_effect+m_effect) %>%
                      pull(y_hat)
    RMSE <- function(y, y_hat){
        sqrt(mean((y - y_hat)^2))
    }
    return(RMSE(y_hat, test$rating))
}

movie_predict <- function(train, test) {
    mu <- mean(train$rating)
    movie_effects <- train %>% group_by(movieId) %>% summarize(mean = mean(rating-mu))
    movie_effects <- left_join(select(test, movieId), movie_effects, by="movieId")
    y_hat <- mu + movie_effects$mean
    y_hat[is.na(y_hat) == TRUE] <- mu
    return(RMSE(test$rating, y_hat))
}
releaseyear_movie_predict <- function(train, test) {
    mu <- mean(train$rating)
    releaseyear_effects <- train %>% group_by(releaseyear) %>%
                              summarize(ry_effect = mean(rating-mu))
    movie_effects <- train %>% left_join(releaseyear_effects, by="releaseyear") %>%
                                     group_by(movieId) %>%
                                     summarize(m_effect = mean(rating-mu-ry_effect))
    y_hat <- test %>% left_join(releaseyear_effects, by="releaseyear") %>%
                      left_join(movie_effects, by="movieId") %>% 
                      mutate(y_hat = mu+m_effect+ry_effect) %>%
                      pull(y_hat)
    return(RMSE(test$rating, y_hat))
}
week_releaseyear_movie_predict <- function(train, test) {
    mu <- mean(train$rating)
    week_effects <- train %>% group_by(week) %>%
                              summarize(w_effect = mean(rating-mu))
    releaseyear_effects <- train %>% left_join(week_effects, by="week") %>%
                                     group_by(releaseyear) %>%
                                     summarize(ry_effect = mean(rating-mu-w_effect))
    movie_effects <- train %>% left_join(week_effects, by="week") %>%
                               left_join(releaseyear_effects, by="releaseyear") %>%
                               group_by(movieId) %>%
                               summarize(m_effect = mean(rating-mu-w_effect-ry_effect))
    y_hat <- test %>% left_join(week_effects, by="week") %>% 
                      left_join(releaseyear_effects, by="releaseyear") %>%
                      left_join(movie_effects, by="movieId") %>%
                      mutate(y_hat = mu+w_effect+ry_effect+m_effect) %>%
                      pull(y_hat)
    return(RMSE(test$rating, y_hat))
}
drama_week_releaseyear_movie_predict <- function(train, test) {
    mu <- mean(train$rating)
    drama_effects <- train %>% group_by(Drama) %>%
                               summarize(d_effect = mean(rating-mu))
    week_effects <- train %>% left_join(drama_effects, by="Drama") %>%
                              group_by(week) %>%
                              summarize(w_effect = mean(rating-mu-d_effect))
    releaseyear_effects <- train %>% left_join(drama_effects, by="Drama") %>%
                               left_join(week_effects, by="week") %>%
                               group_by(releaseyear) %>%
                               summarize(ry_effect = mean(rating-mu-d_effect-w_effect))
    movie_effects <- train %>% left_join(drama_effects, by="Drama") %>%
                              left_join(week_effects, by="week") %>%
                              left_join(releaseyear_effects, by="releaseyear") %>%
                              group_by(movieId) %>%
                              summarize(m_effect = mean(rating-mu-d_effect-w_effect-ry_effect))
    y_hat <- test %>% left_join(drama_effects, by="Drama") %>% 
                      left_join(week_effects, by="week") %>%
                      left_join(releaseyear_effects, by="releaseyear") %>%
                      left_join(movie_effects, by="movieId") %>%
                      mutate(y_hat = mu+d_effect+w_effect+ry_effect+m_effect) %>%
                      pull(y_hat)
    return(RMSE(test$rating, y_hat))
}


results <- data.frame(method = "Mean", RMSE = mu_predict(train, test))
results <- rbind(results, data.frame(method = "Users", RMSE = user_predict(train, test)))
results <- rbind(results, data.frame(method = "Users+Movies", RMSE = user_movie_predict(train, test)))
#results <- rbind(results, data.frame(method = "Users+Movies (penalized)", RMSE = user_movie_effects_penalized_predict(10,10,train, test)))
results <- rbind(results, data.frame(method = "Movies", RMSE = movie_predict(train, test)))
results <- rbind(results, data.frame(method = "Movies+ReleaseYear", RMSE = releaseyear_movie_predict(train, test)))
results <- rbind(results, data.frame(method = "Movies+ReleaseYear+Drama", RMSE = week_releaseyear_movie_predict(train, test)))
results <- rbind(results, data.frame(method = "Movies+ReleaseYear+Drama+Week", RMSE = drama_week_releaseyear_movie_predict(train, test)))
print(results)

user_movie_effects_penalized <- function(train, lambda1, lambda2) {
    mu <- mean(train$rating)
    user_effects <- train %>% group_by(userId) %>%
                              summarize(u_effect = sum(rating-mu)/(n()+lambda1))
    movie_effects <- train %>% left_join(user_effects, by="userId") %>%
                               group_by(movieId) %>%
                               summarize(m_effect = sum(rating-mu-u_effect)/(n()+lambda2))
    y_hat <- train %>% left_join(user_effects, by="userId") %>% 
                      left_join(movie_effects, by="movieId") %>%
                      mutate(y_hat = mu+u_effect+m_effect) %>%
                      pull(y_hat)
    return(y_hat)
}

user_movie_effects_penalized_predict <- function(lambda1, lambda2, train, test) {
    library(dplyr)
    mu <- mean(train$rating)
    user_effects <- train %>% group_by(userId) %>%
                              summarize(u_effect = sum(rating-mu)/(n()+lambda1))
    movie_effects <- train %>% left_join(user_effects, by="userId") %>%
                               group_by(movieId) %>%
                               summarize(m_effect = sum(rating-mu-u_effect)/(n()+lambda2))
    y_hat <- test %>% left_join(user_effects, by="userId") %>% 
                      left_join(movie_effects, by="movieId") %>%
                      mutate(y_hat = mu+u_effect+m_effect) %>%
                      pull(y_hat)
    RMSE <- function(y, y_hat){
        sqrt(mean((y - y_hat)^2))
    }
    return(RMSE(y_hat, test$rating))
}

#There can be a lambda for each factor vs. one lambda for all factors. These are 
#not overly difficult to tune independently.
library(parallel)
cl <- makeCluster(detectCores()/2)
penalized_tune <- parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 0.0, train, test)
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 0.5, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 1.0, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 1.5, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 2.0, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 2.5, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 3.0, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 3.5, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 4.0, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 4.5, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 5.0, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 5.5, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 6.0, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 6.5, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 7.0, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 7.5, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 8.0, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 8.5, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 9.0, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 9.5, train, test))
penalized_tune <- cbind(penalized_tune, parSapplyLB(cl,seq(0,20,.5), user_movie_effects_penalized_predict, 10.0, train, test))
stopCluster(cl)
print(penalized_tune)
filled.contour(seq(0,20,.5),seq(0,10,.5),penalized_tune,xlab="lambda1",ylab="lambda2")

lambda1 <- 17.5
lambda2 <- 2.5
pm_RMSE <- user_movie_effects_penalized_predict(lambda1, lambda2, train, test)
cat("hybrid model 1 RMSE = ", pm_RMSE, "\n")

mu <- mean(train$rating)
user_effects <- train %>% group_by(userId) %>%
                          summarize(u_effect = sum(rating-mu)/(n()+lambda1))
movie_effects <- train %>% left_join(user_effects, by="userId") %>%
                          group_by(movieId) %>%
                          summarize(m_effect = sum(rating-mu-u_effect)/(n()+lambda2))
y_hat <- train %>% left_join(user_effects, by="userId") %>% 
                  left_join(movie_effects, by="movieId") %>%
                  mutate(y_hat = mu+u_effect+m_effect) %>%
                  pull(y_hat)
train2 <- train %>% mutate(residual=rating-y_hat) %>% select(-userId,-movieId,-rating)
fit <- rpart(residual ~ ., data=train2, control=rpart.control(cp = .0002, maxsurrogate=0))
plot(fit, margin = 0.1)
text(fit, cex = 0.75)
fit <- rpart(residual ~ ., data=train2, control=rpart.control(cp = 0,minsplit=500, maxsurrogate=0))
print(fit$variable.importance)
barplot(fit$variable.importance, las=2)

y_hat <- test %>% left_join(user_effects, by="userId") %>% 
                  left_join(movie_effects, by="movieId") %>%
                  mutate(y_hat = mu+u_effect+m_effect) %>%
                  pull(y_hat)
test2 <- test %>% mutate(residual=rating-y_hat) %>% select(-userId,-movieId,-rating)
hm1_RMSE <- RMSE(test$rating, y_hat+predict(fit, newdata=test2))
cat("hybrid model 1 RMSE = ", hm1_RMSE, "\n")
rm(user_effects,movie_effects,y_hat,train2,test2,fit)
gc()


hybrid_model_1_predict <- function(minsplit, train, test) {
    gc()
    library(dplyr)
    library(rpart)
    lambda1 <- 17.5
    lambda2 <- 2.5
    mu <- mean(train$rating)
    user_effects <- train %>% group_by(userId) %>%
                              summarize(u_effect = sum(rating-mu)/(n()+lambda1))
    movie_effects <- train %>% left_join(user_effects, by="userId") %>%
                               group_by(movieId) %>%
                               summarize(m_effect = sum(rating-mu-u_effect)/(n()+lambda2))
    y_hat <- train %>% left_join(user_effects, by="userId") %>% 
                      left_join(movie_effects, by="movieId") %>%
                      mutate(y_hat = mu+u_effect+m_effect) %>%
                      pull(y_hat)
    train <- train %>% mutate(residual = rating - y_hat)
    fit <- rpart(residual ~ .-rating-userId-movieId, data=train, control=rpart.control(cp = 0,minsplit=minsplit, maxsurrogate=0))
    print(fit$variable.importance)
    y_hat <- test %>% left_join(user_effects, by="userId") %>% 
                      left_join(movie_effects, by="movieId") %>%
                      mutate(y_hat = mu+u_effect+m_effect) %>%
                      pull(y_hat)
    y_hat <- y_hat + predict(fit, newdata=test)
    RMSE <- function(y, y_hat){
        sqrt(mean((y - y_hat)^2))
    }
    return(RMSE(test$rating, y_hat))
}
cl <- makeCluster(2)
tune3 <- c(100000,50000,20000,10000,5000,2000,1000,500,200)
hybrid_1_tune <- parSapplyLB(cl, tune3, hybrid_model_1_predict, train, test)
plot(tune3, hybrid_1_tune, type="b")
stopCluster(cl)
gc()
rmse_1 <- hybrid_model_1_predict(2000,train, test)
cat("Model with penalized effects plus tree, RMSE=", rmse_1, "\n")

hybrid_model_1 <- function(minsplit, train, test) {
    gc()
    library(dplyr)
    library(rpart)
    lambda1 <- 17.5
    lambda2 <- 2.5
    mu <- mean(train$rating)
    user_effects <- train %>% group_by(userId) %>%
                              summarize(u_effect = sum(rating-mu)/(n()+lambda1))
    movie_effects <- train %>% left_join(user_effects, by="userId") %>%
                               group_by(movieId) %>%
                               summarize(m_effect = sum(rating-mu-u_effect)/(n()+lambda2))
    y_hat <- train %>% left_join(user_effects, by="userId") %>% 
                      left_join(movie_effects, by="movieId") %>%
                      mutate(y_hat = mu+u_effect+m_effect) %>%
                      pull(y_hat)
    train <- train %>% mutate(residual = rating - y_hat)
    fit <- rpart(residual ~ .-rating-userId-movieId, data=train, control=rpart.control(cp = 0,minsplit=minsplit, maxsurrogate=0))
    return(fit)
}
fit <- hybrid_model_1(2000,train,test)
print(fit$variable.importance)
barplot(fit$variable.importance, las=2)
rm(fit)
gc()

# Try a generalized additive model on the 3 most important variables from the residual
hybrid_model_2 <- function(train, test) {
    gc()
    library(mgcv)
    library(dplyr)
    library(parallel)
    library(rpart)
    lambda1 <- 17.5
    lambda2 <- 2.5
    mu <- mean(train$rating)
    user_effects <- train %>% group_by(userId) %>%
                              summarize(u_effect = sum(rating-mu)/(n()+lambda1))
    movie_effects <- train %>% left_join(user_effects, by="userId") %>%
                               group_by(movieId) %>%
                               summarize(m_effect = sum(rating-mu-u_effect)/(n()+lambda2))
    y_hat <- train %>% left_join(user_effects, by="userId") %>% 
                      left_join(movie_effects, by="movieId") %>%
                      mutate(y_hat = mu+u_effect+m_effect) %>%
                      pull(y_hat)
    train <- train %>% mutate(residual = rating - y_hat)
    fit <- bam(residual ~ s(as.numeric(week),bs="cs")+s(releaseyear,bs="cs")+s(day,bs="cs"),
               data=train, gc.level=2)
    return(fit)
}

fit <- hybrid_model_2(train,test)
print(summary(fit))

hybrid_model_2_predict <- function(train, test) {
    gc()
    library(mgcv)
    library(dplyr)
    library(parallel)
    library(rpart)
    lambda1 <- 17.5
    lambda2 <- 2.5
    cl <- makeCluster(detectCores()/4)
    mu <- mean(train$rating)
    user_effects <- train %>% group_by(userId) %>%
                              summarize(u_effect = sum(rating-mu)/(n()+lambda1))
    movie_effects <- train %>% left_join(user_effects, by="userId") %>%
                               group_by(movieId) %>%
                               summarize(m_effect = sum(rating-mu-u_effect)/(n()+lambda2))
    y_hat <- train %>% left_join(user_effects, by="userId") %>% 
                      left_join(movie_effects, by="movieId") %>%
                      mutate(y_hat = mu+u_effect+m_effect) %>%
                      pull(y_hat)
    train <- train %>% mutate(residual = rating - y_hat)
    fit <- bam(residual ~ s(as.numeric(week),bs="cs")+s(releaseyear,bs="cs")+s(day,bs="cs"),
               data=train, gc.level=2, cluster=cl)
    print(fit$variable.importance)
    y_hat <- test %>% left_join(user_effects, by="userId") %>% 
                      left_join(movie_effects, by="movieId") %>%
                      mutate(y_hat = mu+u_effect+m_effect) %>%
                      pull(y_hat)
    y_hat <- y_hat + predict(fit, newdata=test)
    RMSE <- function(y, y_hat){
        sqrt(mean((y - y_hat)^2))
    }
    stopCluster(cl)
    return(RMSE(test$rating, y_hat))
}
rmse_2 <- hybrid_model_2_predict(train, test)
cat("Model with penalized effects plus GAM, RMSE=", rmse_2)
rm(train,test)

#Use model 1 (penalized least squares plus regression tree) to predict validation set
gc()
edx <- wrangle(edx)
validation <- wrangle(validation)
 
final_RMSE <- hybrid_model_1_predict(2000,edx, validation)
cat("Final RMSE for full edx/validation sets = ", final_RMSE)