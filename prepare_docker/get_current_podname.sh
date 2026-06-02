#!/bin/bash

export POD=$(kc get pods -n weblogic -l app=wls-admin -o jsonpath='{.items[0].metadata.name}')
