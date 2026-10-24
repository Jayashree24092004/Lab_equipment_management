import mysql.connector
from flask import current_app


def get_connection():
    return mysql.connector.connect(**current_app.config['MYSQL_CONFIG'])


def query(sql, params=(), fetchone=False, dictionary=True):
    conn = get_connection()
    cur = conn.cursor(dictionary=dictionary)
    try:
        cur.execute(sql, params)
        result = cur.fetchone() if fetchone else cur.fetchall()
        conn.commit()
        return result
    finally:
        cur.close()
        conn.close()


def execute(sql, params=()):
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(sql, params)
        conn.commit()
        return cur.lastrowid
    finally:
        cur.close()
        conn.close()


def call_procedure(name, args=()):
    conn = get_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.callproc(name, args)
        result_sets = []
        for result in cur.stored_results():
            result_sets.append(result.fetchall())
        conn.commit()
        return result_sets
    finally:
        cur.close()
        conn.close()
