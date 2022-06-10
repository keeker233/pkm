import pymysql
import re
from py2neo import Graph, Node, Relationship

db = pymysql.connect(host="127.0.0.1",user="jo", password="123", database="wizksent",charset="utf8")
cursor = db.cursor()
sql = "select * from wiz_document"
cursor.execute(sql)
data=cursor.fetchall()
print(data)
db.close()

result1 = re.findall(".*%s(.*)%s.*"%('&','&'),str(data))
print(result1)

graph = Graph('http://localhost:7474', auth=("neo4j", "neo4j"))

for x in result1:
    # 初始化节点
    node_1 = Node(x, name="name_1")
    # 创建节点
    graph.create(node_1)
    # 初始化关系
    #relation_1_a = Relationship(node_1, relation_name, node_a)
    # 创建关系
    #graph.create(relation_1_a)
