DROP TABLE part;

-- data setup
CREATE TABLE part( 
    p_partkey INT,
    p_name STRING,
    p_mfgr STRING,
    p_brand STRING,
    p_type STRING,
    p_size INT,
    p_container STRING,
    p_retailprice DOUBLE,
    p_comment STRING
);

LOAD DATA LOCAL INPATH '../data/files/part_tiny.txt' overwrite into table part;

-- 1. testWindowing
select p_mfgr, p_name, p_size,
rank() as r,
dense_rank() as dr,
sum(p_retailprice) over (rows between unbounded preceding and current row) as s1
from part
distribute by p_mfgr
sort by p_name;

-- 2. testGroupByWithPartitioning
select p_mfgr, p_name, p_size, min(p_retailprice),
rank() as r,
dense_rank() as dr,
p_size, p_size - lag(p_size,1,p_size) as deltaSz
from part
group by p_mfgr, p_name, p_size
distribute by p_mfgr
sort by p_name ;
       
-- 3. testGroupByHavingWithSWQ
select p_mfgr, p_name, p_size, min(p_retailprice),
rank() as r,
dense_rank() as dr,
p_size, p_size - lag(p_size,1,p_size) as deltaSz
from part
group by p_mfgr, p_name, p_size
having p_size > 0
distribute by p_mfgr
sort by p_name ;

-- 4. testCount
select p_mfgr, p_name, 
count(p_size) as cd 
from part 
distribute by p_mfgr 
sort by p_name;

-- 5. testCountWithWindowingUDAF
select p_mfgr, p_name, 
rank() as r, 
dense_rank() as dr, 
count(p_size) as cd, 
p_retailprice, sum(p_retailprice) over (rows between unbounded preceding and current row) as s1, 
p_size, p_size - lag(p_size,1,p_size) as deltaSz 
from part 
distribute by p_mfgr 
sort by p_name;

-- 6. testCountInSubQ
select sub1.r, sub1.dr, sub1.cd, sub1.s1, sub1.deltaSz 
from (select p_mfgr, p_name, 
rank() as r, 
dense_rank() as dr, 
count(p_size) as cd, 
p_retailprice, sum(p_retailprice) over (rows between unbounded preceding and current row) as s1, 
p_size, p_size - lag(p_size,1,p_size) as deltaSz 
from part 
distribute by p_mfgr 
sort by p_name
) sub1;

-- 7. testJoinWithWindowingAndPTF
select abc.p_mfgr, abc.p_name, 
rank() as r, 
dense_rank() as dr, 
abc.p_retailprice, sum(abc.p_retailprice) over (rows between unbounded preceding and current row) as s1, 
abc.p_size, abc.p_size - lag(abc.p_size,1,abc.p_size) as deltaSz 
from noop(on part 
partition by p_mfgr 
order by p_name 
) abc join part p1 on abc.p_partkey = p1.p_partkey 
distribute by abc.p_mfgr 
sort by abc.p_name ;

-- 8. testMixedCaseAlias
select p_mfgr, p_name, p_size, rank() as R
from part 
distribute by p_mfgr 
sort by p_name, p_size desc;

-- 9. testHavingWithWindowingNoGBY
select p_mfgr, p_name, p_size, 
rank() as r, 
dense_rank() as dr, 
sum(p_retailprice) over (rows between unbounded preceding and current row)  as s1
from part 
having p_size > 5 
distribute by p_mfgr 
sort by p_name; 

-- 10. testHavingWithWindowingCondRankNoGBY
select p_mfgr, p_name, p_size, 
rank() as r, 
dense_rank() as dr, 
sum(p_retailprice) over (rows between unbounded preceding and current row) as s1 
from part 
having rank() < 4 
distribute by p_mfgr 
sort by p_name;

-- 11. testFirstLast   
select  p_mfgr,p_name, p_size, 
sum(p_size) over (rows between current row and current row) as s2, 
first_value(p_size) over w1  as f, 
last_value(p_size, false) over w1  as l 
from part 
distribute by p_mfgr 
sort by p_mfgr 
window w1 as (rows between 2 preceding and 2 following);

-- 12. testFirstLastWithWhere
select  p_mfgr,p_name, p_size, 
rank() as r, 
sum(p_size) over (rows between current row and current row) as s2, 
first_value(p_size) over w1 as f,  
last_value(p_size, false) over w1 as l 
from part 
where p_mfgr = 'Manufacturer#3' 
distribute by p_mfgr 
sort by p_mfgr 
window w1 as (rows between 2 preceding and 2 following);

-- 13. testSumWindow
select  p_mfgr,p_name, p_size,  
sum(p_size) over w1 as s1, 
sum(p_size) over (rows between current row and current row)  as s2 
from part 
distribute by p_mfgr 
sort by p_mfgr 
window w1 as (rows between 2 preceding and 2 following);

-- 14. testNoSortClause
select  p_mfgr,p_name, p_size, 
rank() as r, dense_rank() as dr 
from part 
distribute by p_mfgr 
window w1 as (rows between 2 preceding and 2 following);

-- 15. testExpressions
select  p_mfgr,p_name, p_size,  
rank() as r,  
dense_rank() as dr, 
cume_dist() as cud, 
percent_rank() as pr, 
ntile(3) as nt, 
count(p_size) as ca, 
avg(p_size) as avg, 
stddev(p_size) as st, 
first_value(p_size % 5) as fv, 
last_value(p_size) as lv, 
first_value(p_size, true) over w1  as fvW1
from part 
having p_size > 5 
distribute by p_mfgr 
sort by p_mfgr, p_name 
window w1 as (rows between 2 preceding and 2 following);

-- 16. testMultipleWindows
select  p_mfgr,p_name, p_size,  
  rank() as r, dense_rank() as dr, 
cume_dist() as cud, 
sum(p_size) over (rows between unbounded preceding and current row) as s1, 
sum(p_size) over (range between p_size 5 less and current row) as s2, 
first_value(p_size, true) over w1  as fv1
from part 
having p_size > 5 
distribute by p_mfgr 
sort by p_mfgr, p_name 
window w1 as (rows between 2 preceding and 2 following);

-- 17. testCountStar
select  p_mfgr,p_name, p_size,
count(*) as c, 
count(p_size) as ca, 
first_value(p_size, true) over w1  as fvW1
from part 
having p_size > 5 
distribute by p_mfgr 
sort by p_mfgr, p_name 
window w1 as (rows between 2 preceding and 2 following);

-- 18. testUDAFs
select  p_mfgr,p_name, p_size, 
sum(p_retailprice) over w1 as s, 
min(p_retailprice) over w1 as mi,
max(p_retailprice) over w1 as ma,
avg(p_retailprice) over w1 as ag
from part
distribute by p_mfgr
sort by p_mfgr, p_name
window w1 as (rows between 2 preceding and 2 following);

-- 19. testUDAFsWithGBY
select  p_mfgr,p_name, p_size, p_retailprice, 
sum(p_retailprice) over w1 as s, 
min(p_retailprice) as mi ,
max(p_retailprice) as ma ,
avg(p_retailprice) over w1 as ag
from part
group by p_mfgr,p_name, p_size, p_retailprice
distribute by p_mfgr
sort by p_mfgr, p_name
window w1 as (rows between 2 preceding and 2 following);

-- 20. testSTATs
select  p_mfgr,p_name, p_size, 
stddev(p_retailprice) over w1 as sdev, 
stddev_pop(p_retailprice) over w1 as sdev_pop, 
collect_set(p_size) over w1 as uniq_size, 
variance(p_retailprice) over w1 as var,
corr(p_size, p_retailprice) over w1 as cor,
covar_pop(p_size, p_retailprice) over w1 as covarp
from part
distribute by p_mfgr
sort by p_mfgr, p_name
window w1 as (rows between 2 preceding and 2 following);

-- 21. testDISTs
select  p_mfgr,p_name, p_size, 
histogram_numeric(p_retailprice, 5) over w1 as hist, 
percentile(p_partkey, 0.5) over w1 as per,
row_number() as rn
from part
distribute by p_mfgr
sort by p_mfgr, p_name
window w1 as (rows between 2 preceding and 2 following);

-- 22. testViewAsTableInputWithWindowing
create view IF NOT EXISTS mfgr_price_view as 
select p_mfgr, p_brand, 
sum(p_retailprice) as s 
from part 
group by p_mfgr, p_brand;
        
select p_mfgr, p_brand, s, 
sum(s) over w1  as s1
from mfgr_price_view 
distribute by p_mfgr 
sort by p_mfgr 
window w1 as (rows between 2 preceding and current row);

-- 23. testCreateViewWithWindowingQuery
create view IF NOT EXISTS mfgr_brand_price_view as 
select p_mfgr, p_brand, 
sum(p_retailprice) over w1  as s
from part 
distribute by p_mfgr 
sort by p_mfgr 
window w1 as (rows between 2 preceding and current row);
        
select * from mfgr_brand_price_view;        
        
-- 24. testLateralViews
select p_mfgr, p_name, 
lv_col, p_size, sum(p_size) over w1   as s
from (select p_mfgr, p_name, p_size, array(1,2,3) arr from part) p 
lateral view explode(arr) part_lv as lv_col
distribute by p_mfgr 
sort by p_name 
window w1 as (rows between 2 preceding and current row);        

-- 25. testMultipleInserts3SWQs
CREATE TABLE part_1( 
p_mfgr STRING, 
p_name STRING, 
p_size INT, 
r INT, 
dr INT, 
s DOUBLE);

CREATE TABLE part_2( 
p_mfgr STRING, 
p_name STRING, 
p_size INT, 
r INT, 
dr INT, 
cud INT, 
s1 DOUBLE, 
s2 DOUBLE, 
fv1 INT);

CREATE TABLE part_3( 
p_mfgr STRING, 
p_name STRING, 
p_size INT, 
c INT, 
ca INT, 
fv INT);

from part 
INSERT OVERWRITE TABLE part_1 
select p_mfgr, p_name, p_size, 
rank() as r, 
dense_rank() as dr, 
sum(p_retailprice) over (rows between unbounded preceding and current row)  as s
distribute by p_mfgr 
sort by p_name  
INSERT OVERWRITE TABLE part_2 
select  p_mfgr,p_name, p_size,  
rank() as r, dense_rank() as dr, 
cume_dist() as cud, 
sum(p_size) over (rows between unbounded preceding and current row) as s1, 
sum(p_size) over (range between p_size 5 less and current row) as s2, 
first_value(p_size, true) over w1  as fv1
having p_size > 5 
distribute by p_mfgr 
sort by p_mfgr, p_name 
window w1 as (rows between 2 preceding and 2 following) 
INSERT OVERWRITE TABLE part_3 
select  p_mfgr,p_name, p_size,  
count(*) as c, 
count(p_size) as ca, 
first_value(p_size, true) over w1  as fv
having p_size > 5 
distribute by p_mfgr 
sort by p_mfgr, p_name 
window w1 as (rows between 2 preceding and 2 following);

select * from part_1;

select * from part_2;

select * from part_3;

-- 26. testGroupByHavingWithSWQAndAlias
select p_mfgr, p_name, p_size, min(p_retailprice) as mi,
rank() as r,
dense_rank() as dr,
p_size, p_size - lag(p_size,1,p_size) as deltaSz
from part
group by p_mfgr, p_name, p_size
having p_size > 0
distribute by p_mfgr
sort by p_name;
	 
-- 27. testMultipleRangeWindows
select  p_mfgr,p_name, p_size, 
sum(p_size) over (range between p_size 10 less and current row) as s2, 
sum(p_size) over (range between current row and p_size 10 more )  as s1
from part 
distribute by p_mfgr 
sort by p_mfgr, p_size 
window w1 as (rows between 2 preceding and 2 following);

-- 28. testPartOrderInUDAFInvoke
select p_mfgr, p_name, p_size,
sum(p_size) over (partition by p_mfgr  order by p_name  rows between 2 preceding and 2 following) as s
from part;

-- 29. testPartOrderInWdwDef
select p_mfgr, p_name, p_size,
sum(p_size) over w1 as s
from part
window w1 as (partition by p_mfgr  order by p_name  rows between 2 preceding and 2 following);

-- 30. testDefaultPartitioningSpecRules
select p_mfgr, p_name, p_size,
sum(p_size) over w1 as s,
sum(p_size) over w2 as s2
from part
sort by p_name
window w1 as (partition by p_mfgr rows between 2 preceding and 2 following),
       w2 as (partition by p_mfgr order by p_name);
       
-- 31. testWindowCrossReference
select p_mfgr, p_name, p_size, 
sum(p_size) over w1 as s1, 
sum(p_size) over w2 as s2
from part 
window w1 as (partition by p_mfgr order by p_mfgr rows between 2 preceding and 2 following), 
       w2 as w1;
       
               
-- 32. testWindowInheritance
select p_mfgr, p_name, p_size, 
sum(p_size) over w1 as s1, 
sum(p_size) over w2 as s2 
from part 
window w1 as (partition by p_mfgr order by p_mfgr rows between 2 preceding and 2 following), 
       w2 as (w1 rows between unbounded preceding and current row); 

        
-- 33. testWindowForwardReference
select p_mfgr, p_name, p_size, 
sum(p_size) over w1 as s1, 
sum(p_size) over w2 as s2,
sum(p_size) over w3 as s3
from part 
distribute by p_mfgr 
sort by p_mfgr 
window w1 as (rows between 2 preceding and 2 following), 
       w2 as w3,
       w3 as (rows between unbounded preceding and current row); 


-- 34. testWindowDefinitionPropagation
select p_mfgr, p_name, p_size, 
sum(p_size) over w1 as s1, 
sum(p_size) over w2 as s2,
sum(p_size) over (w3 rows between 2 preceding and 2 following)  as s3
from part 
distribute by p_mfgr 
sort by p_mfgr 
window w1 as (rows between 2 preceding and 2 following), 
       w2 as w3,
       w3 as (rows between unbounded preceding and current row); 

-- 35. testDistinctWithWindowing
select DISTINCT p_mfgr, p_name, p_size,
sum(p_size) over w1 as s
from part
distribute by p_mfgr
sort by p_name
window w1 as (rows between 2 preceding and 2 following);

-- 36. testRankWithPartitioning
select p_mfgr, p_name, p_size, 
rank() over (partition by p_mfgr order by p_name )  as r
from part;    

-- 37. testPartitioningVariousForms
select p_mfgr, p_name, p_size,
sum(p_retailprice) over (partition by p_mfgr order by p_mfgr) as s1,
min(p_retailprice) over (partition by p_mfgr) as s2,
max(p_retailprice) over (distribute by p_mfgr sort by p_mfgr) as s3,
avg(p_retailprice) over (distribute by p_mfgr) as s4,
count(p_retailprice) over (cluster by p_mfgr ) as s5
from part;

-- 38. testPartitioningVariousForms2
select p_mfgr, p_name, p_size,
sum(p_retailprice) over (partition by p_mfgr, p_name order by p_mfgr, p_name rows between unbounded preceding and current row) as s1,
min(p_retailprice) over (distribute by p_mfgr, p_name sort by p_mfgr, p_name rows between unbounded preceding and current row) as s2,
max(p_retailprice) over (cluster by p_mfgr, p_name ) as s3
from part;

-- 39. testUDFOnOrderCols
select p_mfgr, p_type, substr(p_type, 2) as short_ptype,
rank() over (partition by p_mfgr order by substr(p_type, 2))  as r
from part;

-- 40. testNoBetweenForRows
select p_mfgr, p_name, p_size,
    sum(p_retailprice) over (rows unbounded preceding) as s1
     from part distribute by p_mfgr sort by p_name;

-- 41. testNoBetweenForRange
select p_mfgr, p_name, p_size,
    sum(p_retailprice) over (range unbounded preceding) as s1
     from part distribute by p_mfgr sort by p_name;

-- 42. testUnboundedFollowingForRows
select p_mfgr, p_name, p_size,
    sum(p_retailprice) over (rows between current row and unbounded following) as s1
    from part distribute by p_mfgr sort by p_name;

-- 43. testUnboundedFollowingForRange
select p_mfgr, p_name, p_size,
    sum(p_retailprice) over (range between current row and unbounded following) as s1
    from part distribute by p_mfgr sort by p_name;
        
-- 44. testOverNoPartitionSingleAggregate
select p_name, p_retailprice,
avg(p_retailprice) over()
from part
order by p_name;
        