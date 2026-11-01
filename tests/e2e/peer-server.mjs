// Local PeerJS broker for tests and local development: 127.0.0.1:9000
import { PeerServer } from 'peer'

PeerServer({ host: '127.0.0.1', port: 9000, path: '/' }, () => console.log('PeerJS broker on 127.0.0.1:9000'))
