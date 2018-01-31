#!/usr/bin/env python

# Very simple script to fetch values.xml from a Poseidon device (HW Group, https://hw-group.com/)
# This was tested with Poseidon model 1250 and firmware version 1.9.13
#
# Copyright (c) Oliver Falk, 2018
#               oliver@linux-kernel.at
#
# Changes are welcome, but please consider sending me a pull request.

from requests import get as httpget
from xml.etree.ElementTree import fromstring as xmlparse
import argparse
from sys import exit

parser = argparse.ArgumentParser(description='Fetch values.xml from poseidon device and try to parse it')
parser.add_argument('--host', help='the host to check')
args = parser.parse_args()

if not args.host:
  print Exception('You need to specify a hostname')
  exit(-1)

link = 'http://%s/values.xml' % args.host
poseidonxml = httpget(link)

if poseidonxml.status_code == 200:
  xml = xmlparse(poseidonxml.text)
  devicename = xml.findall('Agent/DeviceName').pop().text
  senset = xml.findall('SenSet').pop()
  print('%s:' % devicename)
  for child in senset.getchildren():
    sensor = {
      'id': child.findall('ID').pop().text,
      'name': child.findall('Name').pop().text,
      'min': child.findall('Min').pop().text,
      'max': child.findall('Max').pop().text,
      'units': child.findall('Units').pop().text,
      'value': child.findall('Value').pop().text,
    }
    print(sensor)
else:
  print("Something went wrong. Status: %s" % poseidonxml.status_code)
