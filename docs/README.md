# Repository README (moved)

This file was moved to `docs/README.md` to collect documentation in the `docs/` folder.

Original content (excerpt):

```
export MK_PRF=wlcluster

alias mk='minikube'
#alias kc='kubectl'
#alias kc="minikube -p $MK_PRF kubectl --"

alias kc="minikube -p wlcluster kubectl

kc get nodes

NAME            STATUS     ROLES           AGE   VERSION
wlcluster       Ready      control-plane   79m   v1.35.0
wlcluster-m02   NotReady   <none>          77m   v1.35.0
wlcluster-m03   NotReady   <none>          75m   v1.35.0
wlcluster-m04   NotReady   <none>          74m   v1.35.0
```

Please refer to `docs/WEBLOGIC_DEPLOYMENT.md` and `docs/ANSIBLE.md` for project documentation.

